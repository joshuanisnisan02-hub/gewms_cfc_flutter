-- Gas receipt upload storage support for GEWMS Flutter.
-- Apply after 20260620000000_gewms_flutter_compat.sql.

-- Private bucket for gas receipt images/PDFs.
insert into storage.buckets (id, name, public)
values ('gas-receipts', 'gas-receipts', false)
on conflict (id) do nothing;

-- Add metadata columns used by the Flutter upload flow while keeping legacy columns intact.
alter table if exists public.gas_receipts add column if not exists transaction_id bigint;
alter table if exists public.gas_receipts add column if not exists file_path text;
alter table if exists public.gas_receipts add column if not exists file_name text;
alter table if exists public.gas_receipts add column if not exists content_type text;
alter table if exists public.gas_receipts add column if not exists uploaded_by uuid references auth.users(id) on delete set null;
alter table if exists public.gas_receipts add column if not exists uploaded_at timestamptz default now();

-- Add a relationship when both tables exist and the constraint has not already been created.
do $$
begin
  if to_regclass('public.gas_receipts') is not null
     and to_regclass('public.gas_transactions') is not null
     and not exists (
       select 1 from pg_constraint where conname = 'gas_receipts_transaction_id_fkey'
     ) then
    alter table public.gas_receipts
      add constraint gas_receipts_transaction_id_fkey
      foreign key (transaction_id) references public.gas_transactions(id) on delete cascade;
  end if;
end;
$$;

create index if not exists gas_receipts_transaction_id_idx on public.gas_receipts(transaction_id);
create index if not exists gas_receipts_uploaded_at_idx on public.gas_receipts(uploaded_at desc);

alter table if exists public.gas_receipts enable row level security;

drop policy if exists authenticated_gas_receipts_all on public.gas_receipts;
create policy authenticated_gas_receipts_all on public.gas_receipts
for all to authenticated
using (true)
with check (true);

-- Storage object policies for authenticated app users.
drop policy if exists authenticated_gas_receipts_storage_read on storage.objects;
create policy authenticated_gas_receipts_storage_read on storage.objects
for select to authenticated
using (bucket_id = 'gas-receipts');

drop policy if exists authenticated_gas_receipts_storage_insert on storage.objects;
create policy authenticated_gas_receipts_storage_insert on storage.objects
for insert to authenticated
with check (bucket_id = 'gas-receipts');

drop policy if exists authenticated_gas_receipts_storage_update on storage.objects;
create policy authenticated_gas_receipts_storage_update on storage.objects
for update to authenticated
using (bucket_id = 'gas-receipts')
with check (bucket_id = 'gas-receipts');

drop policy if exists authenticated_gas_receipts_storage_delete on storage.objects;
create policy authenticated_gas_receipts_storage_delete on storage.objects
for delete to authenticated
using (bucket_id = 'gas-receipts');
