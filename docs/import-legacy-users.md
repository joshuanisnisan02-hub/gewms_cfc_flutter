# Import legacy PHPMyAdmin users into Supabase Auth

The Flutter app signs in with Supabase Auth, not the legacy PHP `users` table. Importing rows into `public.profiles` alone is not enough. Every login account must exist in `auth.users`, and then a matching `public.profiles` row stores app metadata such as role and driver ID.

## 1. Export users from PHPMyAdmin

Export your legacy users table as CSV with these columns when possible:

```csv
email,full_name,role,driver_id
admin@example.com,System Administrator,Admin,
driver@example.com,Driver Name,Driver,1
```

Supported alternate column names:

- Email: `email`, `user_email`, or `username`
- Name: `full_name`, `name`, `fullname`, or `display_name`
- Role: `role`, `user_role`, `type`, or `user_type`
- Driver ID: `driver_id` or `driverid`

If a role is not `Driver`, the importer treats it as `Admin`.

## 2. Apply the profile migration

Run:

```bash
supabase db push
```

This applies `supabase/migrations/20260620030000_profiles_auth_mapping.sql`, which ensures `public.profiles` has the columns needed by the app and adds an auth trigger for future users.

## 3. Install importer dependency

The importer uses the Supabase JavaScript client. Install it locally:

```bash
npm install @supabase/supabase-js
```

## 4. Set local environment variables

Use your project URL and service-role key locally. Do not commit the service-role key.

PowerShell:

```powershell
$env:SUPABASE_URL="https://laonbefisynknlnzcnkt.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="your_service_role_key"
$env:DEFAULT_PASSWORD="ChangeMe123!"
```

Bash:

```bash
export SUPABASE_URL="https://laonbefisynknlnzcnkt.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="your_service_role_key"
export DEFAULT_PASSWORD="ChangeMe123!"
```

## 5. Run the import

```bash
node tools/import_legacy_users.mjs path/to/users.csv
```

The script will:

1. create missing Supabase Auth users;
2. confirm their email automatically;
3. set the temporary default password;
4. upsert their matching `public.profiles` row;
5. preserve Admin/Driver role and driver ID metadata.

## 6. Test login

Use the imported email and the temporary default password:

```bash
flutter run -d chrome --dart-define=SUPABASE_KEY=your_publishable_key
```

After users can log in, change their passwords from Supabase Auth or by adding a password-reset flow.
