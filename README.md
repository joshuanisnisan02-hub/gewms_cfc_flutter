# GEWMS CFC Flutter

Flutter migration of the existing GEWMS CFC PHP/XAMPP system. The app uses Supabase project `laonbefisynknlnzcnkt` and keeps the migrated legacy table names so the current data model can be reused.

## Migrated modules

- Dashboard summary for water, electricity, and gas records
- Water billing list, add form, and paid marking
- Electricity billing list, add form, and paid marking
- Gas transaction list with driver filtering through `profiles.driver_id`
- Master data viewer for offices, buildings, drivers, cars, water accounts, and electricity accounts

## Supabase setup

Apply the compatibility migration before running the app:

```bash
supabase db push
```

Or copy the SQL from:

```text
supabase/migrations/20260620000000_gewms_flutter_compat.sql
```

into the Supabase SQL Editor for project `laonbefisynknlnzcnkt`.

The migration fixes the common MySQL-to-Postgres issue where imported `AUTO_INCREMENT` IDs become `bigint` columns without generated defaults. It also adds missing timestamp columns, update triggers, and starter authenticated RLS policies.

## Authentication model

The old PHP `users` table is treated as legacy data. The Flutter app signs in with Supabase Auth and reads user role data from `public.profiles`.

For every Auth user, create or keep a matching profile row:

```sql
insert into public.profiles (id, email, role, driver_id, full_name)
values ('<auth.users.id>', 'admin@example.com', 'Admin', null, 'System Admin');
```

Use `role = 'Admin'` for full access. For driver accounts, set `role = 'Driver'` and assign `driver_id` from the legacy `drivers` table.

## Run locally

Install dependencies:

```bash
flutter pub get
```

Run with your Supabase publishable key:

```bash
flutter run --dart-define=SUPABASE_KEY=your_publishable_key
```

The Supabase URL is already configured in `lib/main.dart` as:

```text
https://laonbefisynknlnzcnkt.supabase.co
```

## Notes

- Do not commit Supabase service-role keys or private API keys.
- Tighten the generated RLS policies before production deployment if different roles need different permissions.
- The current Flutter app is a functional migration foundation; detailed edit/delete screens and file-upload receipt storage can be added next.
