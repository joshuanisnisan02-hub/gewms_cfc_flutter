-- Audit logging for GEWMS production operations.
-- Records insert, update, and delete activity on high-value tables.

create table if not exists public.audit_logs (
  id bigserial primary key,
  table_name text not null,
  record_id text,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  old_data jsonb,
  new_data jsonb,
  changed_at timestamptz not null default now()
);

create index if not exists audit_logs_table_name_changed_at_idx on public.audit_logs (table_name, changed_at desc);
create index if not exists audit_logs_actor_id_changed_at_idx on public.audit_logs (actor_id, changed_at desc);
create index if not exists audit_logs_record_id_idx on public.audit_logs (record_id);

alter table public.audit_logs enable row level security;

drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read on public.audit_logs
for select to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'Admin'
  )
);

drop policy if exists audit_logs_no_client_write on public.audit_logs;
create policy audit_logs_no_client_write on public.audit_logs
for insert to authenticated
with check (false);

create or replace function public.audit_actor_email()
returns text
language sql
stable
as $$
  select email from auth.users where id = auth.uid()
$$;

create or replace function public.audit_record_id(row_data jsonb)
returns text
language sql
immutable
as $$
  select coalesce(
    row_data->>'id',
    row_data->>'billing_id',
    row_data->>'transaction_no',
    row_data->>'office_id',
    row_data->>'building_id',
    row_data->>'account_number'
  )
$$;

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_row jsonb;
  new_row jsonb;
begin
  if tg_op = 'INSERT' then
    old_row := null;
    new_row := to_jsonb(new);
  elsif tg_op = 'UPDATE' then
    old_row := to_jsonb(old);
    new_row := to_jsonb(new);
  elsif tg_op = 'DELETE' then
    old_row := to_jsonb(old);
    new_row := null;
  end if;

  insert into public.audit_logs (
    table_name,
    record_id,
    action,
    actor_id,
    actor_email,
    old_data,
    new_data
  )
  values (
    tg_table_name,
    public.audit_record_id(coalesce(new_row, old_row)),
    tg_op,
    auth.uid(),
    public.audit_actor_email(),
    old_row,
    new_row
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

-- Billing records.
drop trigger if exists audit_water_bills on public.water_bills;
create trigger audit_water_bills
after insert or update or delete on public.water_bills
for each row execute function public.write_audit_log();

drop trigger if exists audit_electricity_bills on public.electricity_bills;
create trigger audit_electricity_bills
after insert or update or delete on public.electricity_bills
for each row execute function public.write_audit_log();

-- Gas operations.
drop trigger if exists audit_gas_transactions on public.gas_transactions;
create trigger audit_gas_transactions
after insert or update or delete on public.gas_transactions
for each row execute function public.write_audit_log();

drop trigger if exists audit_gas_receipts on public.gas_receipts;
create trigger audit_gas_receipts
after insert or update or delete on public.gas_receipts
for each row execute function public.write_audit_log();

-- Master data commonly edited by Admin users.
drop trigger if exists audit_water_accounts on public.water_accounts;
create trigger audit_water_accounts
after insert or update or delete on public.water_accounts
for each row execute function public.write_audit_log();

drop trigger if exists audit_electricity_account on public.electricity_account;
create trigger audit_electricity_account
after insert or update or delete on public.electricity_account
for each row execute function public.write_audit_log();

drop trigger if exists audit_drivers on public.drivers;
create trigger audit_drivers
after insert or update or delete on public.drivers
for each row execute function public.write_audit_log();

drop trigger if exists audit_cars on public.cars;
create trigger audit_cars
after insert or update or delete on public.cars
for each row execute function public.write_audit_log();

grant select on public.audit_logs to authenticated;
