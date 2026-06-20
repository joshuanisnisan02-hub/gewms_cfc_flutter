-- Tighten gas transaction and gas receipt access.
-- Admin users keep full access. Driver users can only see records linked to their profiles.driver_id.

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.profiles where id = auth.uid()), '')
$$;

create or replace function public.current_user_driver_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select (select driver_id::bigint from public.profiles where id = auth.uid())
$$;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(public.current_user_role()) = 'admin'
$$;

create or replace function public.can_access_gas_transaction(transaction_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin_user()
    or exists (
      select 1
      from public.gas_transactions gt
      where gt.id = transaction_id
        and gt.driver_id::bigint = public.current_user_driver_id()
    )
$$;

-- Replace broad gas transaction access.
drop policy if exists authenticated_gas_transactions_all on public.gas_transactions;
drop policy if exists admin_gas_transactions_all on public.gas_transactions;
drop policy if exists drivers_gas_transactions_read_own on public.gas_transactions;

create policy admin_gas_transactions_all on public.gas_transactions
for all to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

create policy drivers_gas_transactions_read_own on public.gas_transactions
for select to authenticated
using (driver_id::bigint = public.current_user_driver_id());

-- Replace broad receipt metadata access.
drop policy if exists authenticated_gas_receipts_all on public.gas_receipts;
drop policy if exists admin_gas_receipts_all on public.gas_receipts;
drop policy if exists drivers_gas_receipts_read_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_insert_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_update_own on public.gas_receipts;
drop policy if exists drivers_gas_receipts_delete_own on public.gas_receipts;

create policy admin_gas_receipts_all on public.gas_receipts
for all to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

create policy drivers_gas_receipts_read_own on public.gas_receipts
for select to authenticated
using (public.can_access_gas_transaction(transaction_id));

create policy drivers_gas_receipts_insert_own on public.gas_receipts
for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and public.can_access_gas_transaction(transaction_id)
);

create policy drivers_gas_receipts_update_own on public.gas_receipts
for update to authenticated
using (
  uploaded_by = auth.uid()
  and public.can_access_gas_transaction(transaction_id)
)
with check (
  uploaded_by = auth.uid()
  and public.can_access_gas_transaction(transaction_id)
);

create policy drivers_gas_receipts_delete_own on public.gas_receipts
for delete to authenticated
using (
  uploaded_by = auth.uid()
  and public.can_access_gas_transaction(transaction_id)
);

-- Storage policies remain permissive enough for the upload-then-insert flow, but reads/updates/deletes
-- are constrained to objects that already have authorized gas_receipts metadata.
drop policy if exists authenticated_gas_receipts_storage_read on storage.objects;
drop policy if exists authenticated_gas_receipts_storage_update on storage.objects;
drop policy if exists authenticated_gas_receipts_storage_delete on storage.objects;
drop policy if exists gas_receipts_storage_read_authorized on storage.objects;
drop policy if exists gas_receipts_storage_update_authorized on storage.objects;
drop policy if exists gas_receipts_storage_delete_authorized on storage.objects;

create policy gas_receipts_storage_read_authorized on storage.objects
for select to authenticated
using (
  bucket_id = 'gas-receipts'
  and exists (
    select 1
    from public.gas_receipts gr
    where gr.file_path = storage.objects.name
      and public.can_access_gas_transaction(gr.transaction_id)
  )
);

create policy gas_receipts_storage_update_authorized on storage.objects
for update to authenticated
using (
  bucket_id = 'gas-receipts'
  and exists (
    select 1
    from public.gas_receipts gr
    where gr.file_path = storage.objects.name
      and (public.is_admin_user() or gr.uploaded_by = auth.uid())
      and public.can_access_gas_transaction(gr.transaction_id)
  )
)
with check (bucket_id = 'gas-receipts');

create policy gas_receipts_storage_delete_authorized on storage.objects
for delete to authenticated
using (
  bucket_id = 'gas-receipts'
  and exists (
    select 1
    from public.gas_receipts gr
    where gr.file_path = storage.objects.name
      and (public.is_admin_user() or gr.uploaded_by = auth.uid())
      and public.can_access_gas_transaction(gr.transaction_id)
  )
);
