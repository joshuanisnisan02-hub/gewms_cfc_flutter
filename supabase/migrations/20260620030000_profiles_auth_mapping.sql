-- Ensure the profiles table supports Supabase Auth based login mapping.
-- Auth users must exist in auth.users. public.profiles stores app role metadata.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  full_name text,
  role text not null default 'Admin',
  driver_id bigint,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists role text not null default 'Admin';
alter table public.profiles add column if not exists driver_id bigint;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();

create unique index if not exists profiles_email_key on public.profiles (email);
create index if not exists profiles_driver_id_idx on public.profiles (driver_id);

alter table public.profiles enable row level security;

drop policy if exists authenticated_profiles_read on public.profiles;
create policy authenticated_profiles_read on public.profiles
for select to authenticated
using (true);

drop policy if exists users_update_own_profile on public.profiles;
create policy users_update_own_profile on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'Admin')
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(public.profiles.full_name, excluded.full_name),
    role = coalesce(public.profiles.role, excluded.role),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
