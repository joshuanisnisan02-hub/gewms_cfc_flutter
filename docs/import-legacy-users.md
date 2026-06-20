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

The importer and verifier use the Supabase JavaScript client. Install it locally:

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

## 6. Verify the import

Run the verifier against the same CSV:

```bash
node tools/verify_legacy_users.mjs path/to/users.csv
```

The verifier checks that every valid CSV row has:

1. a matching Supabase Auth user;
2. a linked `public.profiles` row with the same Auth user ID;
3. the expected email and normalized role;
4. the expected driver ID for Driver accounts.

A successful run exits with status code `0` and prints one `OK` line for each expected user. Any missing Auth user, missing profile, or profile mismatch prints a `FAIL` line and exits with status code `1`.

## 7. Test login

Use the imported email and the temporary default password:

```bash
flutter run -d chrome --dart-define=SUPABASE_KEY=your_publishable_key
```

Minimum manual checks:

1. Admin account can sign in and view all migrated modules.
2. Driver account can sign in and only sees driver-scoped gas transactions for its `driver_id`.
3. Imported users can change their password in Supabase Auth or through the future password-reset flow.

After users can log in, change their passwords from Supabase Auth or by adding a password-reset flow.