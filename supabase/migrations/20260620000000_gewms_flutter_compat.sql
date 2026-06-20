-- GEWMS Flutter compatibility migration
-- Apply this to Supabase project laonbefisynknlnzcnkt.
-- It keeps the migrated PHP/XAMPP table names so the Flutter app can use them directly.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Add missing timestamp columns used by the Flutter app and future edits.
alter table if exists public.water_accounts add column if not exists created_at timestamptz default now();
alter table if exists public.water_accounts add column if not exists updated_at timestamptz default now();
alter table if exists public.water_bills add column if not exists updated_at timestamptz default now();
alter table if exists public.electricity_account add column if not exists created_at timestamptz default now();
alter table if exists public.electricity_bills add column if not exists updated_at timestamptz default now();
alter table if exists public.gas_transactions add column if not exists created_at timestamptz default now();
alter table if exists public.tbl_bldg add column if not exists created_at timestamptz default now();
alter table if exists public.tbl_offices add column if not exists created_at timestamptz default now();
alter table if exists public.drivers add column if not exists created_at timestamptz default now();
alter table if exists public.cars add column if not exists created_at timestamptz default now();

-- Give legacy integer IDs a generated default when they were imported without AUTO_INCREMENT behavior.
create sequence if not exists public.cars_id_seq owned by public.cars.id;
select setval('public.cars_id_seq', coalesce((select max(id) from public.cars), 0) + 1, false);
alter table if exists public.cars alter column id set default nextval('public.cars_id_seq');

create sequence if not exists public.drivers_id_seq owned by public.drivers.id;
select setval('public.drivers_id_seq', coalesce((select max(id) from public.drivers), 0) + 1, false);
alter table if exists public.drivers alter column id set default nextval('public.drivers_id_seq');

create sequence if not exists public.electricity_account_id_seq owned by public.electricity_account.id;
select setval('public.electricity_account_id_seq', coalesce((select max(id) from public.electricity_account), 0) + 1, false);
alter table if exists public.electricity_account alter column id set default nextval('public.electricity_account_id_seq');

create sequence if not exists public.electricity_bills_id_seq owned by public.electricity_bills.id;
select setval('public.electricity_bills_id_seq', coalesce((select max(id) from public.electricity_bills), 0) + 1, false);
alter table if exists public.electricity_bills alter column id set default nextval('public.electricity_bills_id_seq');

create sequence if not exists public.electricity_meter_id_seq owned by public.electricity_meter.id;
select setval('public.electricity_meter_id_seq', coalesce((select max(id) from public.electricity_meter), 0) + 1, false);
alter table if exists public.electricity_meter alter column id set default nextval('public.electricity_meter_id_seq');

create sequence if not exists public.gas_receipts_id_seq owned by public.gas_receipts.id;
select setval('public.gas_receipts_id_seq', coalesce((select max(id) from public.gas_receipts), 0) + 1, false);
alter table if exists public.gas_receipts alter column id set default nextval('public.gas_receipts_id_seq');

create sequence if not exists public.gas_transactions_id_seq owned by public.gas_transactions.id;
select setval('public.gas_transactions_id_seq', coalesce((select max(id) from public.gas_transactions), 0) + 1, false);
alter table if exists public.gas_transactions alter column id set default nextval('public.gas_transactions_id_seq');

create sequence if not exists public.tbl_bldg_building_id_seq owned by public.tbl_bldg.building_id;
select setval('public.tbl_bldg_building_id_seq', coalesce((select max(building_id) from public.tbl_bldg), 0) + 1, false);
alter table if exists public.tbl_bldg alter column building_id set default nextval('public.tbl_bldg_building_id_seq');

create sequence if not exists public.tbl_offices_office_id_seq owned by public.tbl_offices.office_id;
select setval('public.tbl_offices_office_id_seq', coalesce((select max(office_id) from public.tbl_offices), 0) + 1, false);
alter table if exists public.tbl_offices alter column office_id set default nextval('public.tbl_offices_office_id_seq');

create sequence if not exists public.tbl_years_year_id_seq owned by public.tbl_years.year_id;
select setval('public.tbl_years_year_id_seq', coalesce((select max(year_id) from public.tbl_years), 0) + 1, false);
alter table if exists public.tbl_years alter column year_id set default nextval('public.tbl_years_year_id_seq');

create sequence if not exists public.water_accounts_id_seq owned by public.water_accounts.id;
select setval('public.water_accounts_id_seq', coalesce((select max(id) from public.water_accounts), 0) + 1, false);
alter table if exists public.water_accounts alter column id set default nextval('public.water_accounts_id_seq');

create sequence if not exists public.water_bills_id_seq owned by public.water_bills.id;
select setval('public.water_bills_id_seq', coalesce((select max(id) from public.water_bills), 0) + 1, false);
alter table if exists public.water_bills alter column id set default nextval('public.water_bills_id_seq');

-- Keep updated_at fresh where those columns exist.
drop trigger if exists water_accounts_set_updated_at on public.water_accounts;
create trigger water_accounts_set_updated_at before update on public.water_accounts for each row execute function public.set_updated_at();

drop trigger if exists water_bills_set_updated_at on public.water_bills;
create trigger water_bills_set_updated_at before update on public.water_bills for each row execute function public.set_updated_at();

drop trigger if exists electricity_bills_set_updated_at on public.electricity_bills;
create trigger electricity_bills_set_updated_at before update on public.electricity_bills for each row execute function public.set_updated_at();

-- Minimal RLS setup for authenticated app users. Tighten these policies later for production role-by-role access.
alter table if exists public.profiles enable row level security;
alter table if exists public.water_accounts enable row level security;
alter table if exists public.water_bills enable row level security;
alter table if exists public.electricity_account enable row level security;
alter table if exists public.electricity_bills enable row level security;
alter table if exists public.electricity_meter enable row level security;
alter table if exists public.gas_transactions enable row level security;
alter table if exists public.gas_receipts enable row level security;
alter table if exists public.tbl_bldg enable row level security;
alter table if exists public.tbl_offices enable row level security;
alter table if exists public.drivers enable row level security;
alter table if exists public.cars enable row level security;

drop policy if exists authenticated_profiles_read on public.profiles;
create policy authenticated_profiles_read on public.profiles for select to authenticated using (true);

drop policy if exists authenticated_water_accounts_all on public.water_accounts;
create policy authenticated_water_accounts_all on public.water_accounts for all to authenticated using (true) with check (true);

drop policy if exists authenticated_water_bills_all on public.water_bills;
create policy authenticated_water_bills_all on public.water_bills for all to authenticated using (true) with check (true);

drop policy if exists authenticated_electricity_account_all on public.electricity_account;
create policy authenticated_electricity_account_all on public.electricity_account for all to authenticated using (true) with check (true);

drop policy if exists authenticated_electricity_bills_all on public.electricity_bills;
create policy authenticated_electricity_bills_all on public.electricity_bills for all to authenticated using (true) with check (true);

drop policy if exists authenticated_electricity_meter_all on public.electricity_meter;
create policy authenticated_electricity_meter_all on public.electricity_meter for all to authenticated using (true) with check (true);

drop policy if exists authenticated_gas_transactions_all on public.gas_transactions;
create policy authenticated_gas_transactions_all on public.gas_transactions for all to authenticated using (true) with check (true);

drop policy if exists authenticated_gas_receipts_all on public.gas_receipts;
create policy authenticated_gas_receipts_all on public.gas_receipts for all to authenticated using (true) with check (true);

drop policy if exists authenticated_tbl_bldg_read on public.tbl_bldg;
create policy authenticated_tbl_bldg_read on public.tbl_bldg for select to authenticated using (true);

drop policy if exists authenticated_tbl_offices_read on public.tbl_offices;
create policy authenticated_tbl_offices_read on public.tbl_offices for select to authenticated using (true);

drop policy if exists authenticated_drivers_read on public.drivers;
create policy authenticated_drivers_read on public.drivers for select to authenticated using (true);

drop policy if exists authenticated_cars_read on public.cars;
create policy authenticated_cars_read on public.cars for select to authenticated using (true);
