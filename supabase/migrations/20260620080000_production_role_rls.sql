-- Production role-based RLS hardening for the GEWMS Flutter app.
-- Admin users keep full access. Driver users are limited to their own gas trips and receipts.

create or replace function public.current_profile_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_profile_driver_id()
returns bigint
language sql
security definer
set search_path = public
stable
as $$
  select driver_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(public.current_profile_role() = 'Admin', false)
$$;

create or replace function public.is_driver_for_transaction(transaction_id bigint)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.gas_transactions gt
    where gt.id = transaction_id
      and gt.driver_id = public.current_profile_driver_id()
  )
$$;

create or replace function public.is_driver_for_receipt_path(object_name text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when object_name ~ '^transactions/[0-9]+/' then
      public.is_driver_for_transaction(split_part(object_name, '/', 2)::bigint)
    else false
  end
$$;

-- Profiles: users can read/update themselves; Admins can read every profile.
drop policy if exists authenticated_profiles_read on public.profiles;
drop policy if exists users_update_own_profile on public.profiles;
drop policy if exists profiles_read_own on public.profiles;
drop policy if exists profiles_admin_read_all on public.profiles;
drop policy if exists profiles_update_own on public.profiles;

create policy profiles_read_own on public.profiles
for select to authenticated
using (id = auth.uid());

create policy profiles_admin_read_all on public.profiles
for select to authenticated
using (public.is_admin());

create policy profiles_update_own on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Replace broad authenticated table policies with Admin-only policies for billing and master data.
drop policy if exists authenticated_water_accounts_all on public.water_accounts;
drop policy if exists authenticated_water_bills_all on public.water_bills;
drop policy if exists authenticated_electricity_account_all on public.electricity_account;
drop policy if exists authenticated_electricity_bills_all on public.electricity_bills;
drop policy if exists authenticated_electricity_meter_all on public.electricity_meter;
drop policy if exists authenticated_tbl_bldg_read on public.tbl_bldg;
drop policy if exists authenticated_tbl_offices_read on public.tbl_offices;
drop policy if exists authenticated_drivers_read on public.drivers;
drop policy if exists authenticated_cars_read on public.cars;

drop policy if exists admin_water_accounts_all on public.water_accounts;
drop policy if exists admin_water_bills_all on public.water_bills;
drop policy if exists admin_electricity_account_all on public.electricity_account;
drop policy if exists admin_electricity_bills_all on public.electricity_bills;
drop policy if exists admin_electricity_meter_all on public.electricity_meter;
drop policy if exists admin_tbl_bldg_read on public.tbl_bldg;
drop policy if exists admin_tbl_offices_read on public.tbl_offices;
drop policy if exists admin_drivers_read on public.drivers;
drop policy if exists admin_cars_read on public.cars;

create policy admin_water_accounts_all on public.water_accounts
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy admin_water_bills_all on public.water_bills
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy admin_electricity_account_all on public.electricity_account
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy admin_electricity_bills_all on public.electricity_bills
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy admin_electricity_meter_all on public.electricity_meter
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy admin_tbl_bldg_read on public.tbl_bldg
for select to authenticated
using (public.is_admin());

create policy admin_tbl_offices_read on public.tbl_offices
for select to authenticated
using (public.is_admin());

create policy admin_drivers_read on public.drivers
for select to authenticated
using (public.is_admin());

create policy admin_cars_read on public.cars
for select to authenticated
using (public.is_admin());

-- Gas transactions: Admins can manage all rows; Drivers can read only their assigned rows.
drop policy if exists authenticated_gas_transactions_all on public.gas_transactions;
drop policy if exists admin_gas_transactions_all on public.gas_transactions;
drop policy if exists drivers_gas_transactions_read_own on public.gas_transactions;

create policy admin_gas_transactions_all on public.gas_transactions
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy drivers_gas_transactions_read_own on public.gas_transactions
for select to authenticated
using (driver_id = public.current_profile_driver_id());

-- Gas receipts: Admins can manage all rows; Drivers can manage receipts for their assigned transactions.
drop policy if exists authenticated_gas_receipts_all on public.gas_receipts;
drop policy if exists admin_gas_receipts_all on public.gas_receipts;
drop policy if exists drivers_gas_receipts_read_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_insert_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_update_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_delete_own on public.gas_receipts;

create policy admin_gas_receipts_all on public.gas_receipts
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy drivers_gas_receipts_read_own on public.gas_receipts
for select to authenticated
using (public.is_driver_for_transaction(transaction_id));

create policy drivers_gas_receipts_insert_own on public.gas_receipts
for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and public.is_driver_for_transaction(transaction_id)
);

create policy drivers_gas_receipts_update_own on public.gas_receipts
for update to authenticated
using (public.is_driver_for_transaction(transaction_id))
with check (
  uploaded_by = auth.uid()
  and public.is_driver_for_transaction(transaction_id)
);

create policy drivers_gas_receipts_delete_own on public.gas_receipts
for delete to authenticated
using (public.is_driver_for_transaction(transaction_id));

-- Storage bucket and object policies for gas receipt files.
insert into storage.buckets (id, name, public)
values ('gas-receipts', 'gas-receipts', false)
on conflict (id) do nothing;

drop policy if exists admin_gas_receipt_objects_all on storage.objects;
drop policy if exists drivers_gas_receipt_objects_read_own on storage.objects;
drop policy if exists drivers_gas_receipt_objects_insert_own on storage.objects;
drop policy if exists drivers_gas_receipt_objects_update_own on storage.objects;
drop policy if exists drivers_gas_receipt_objects_delete_own on storage.objects;

create policy admin_gas_receipt_objects_all on storage.objects
for all to authenticated
using (bucket_id = 'gas-receipts' and public.is_admin())
with check (bucket_id = 'gas-receipts' and public.is_admin());

create policy drivers_gas_receipt_objects_read_own on storage.objects
for select to authenticated
using (
  bucket_id = 'gas-receipts'
  and public.is_driver_for_receipt_path(name)
);

create policy drivers_gas_receipt_objects_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'gas-receipts'
  and owner = auth.uid()
  and public.is_driver_for_receipt_path(name)
);

create policy drivers_gas_receipt_objects_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'gas-receipts'
  and owner = auth.uid()
  and public.is_driver_for_receipt_path(name)
)
with check (
  bucket_id = 'gas-receipts'
  and owner = auth.uid()
  and public.is_driver_for_receipt_path(name)
);

create policy drivers_gas_receipt_objects_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'gas-receipts'
  and owner = auth.uid()
  and public.is_driver_for_receipt_path(name)
);
