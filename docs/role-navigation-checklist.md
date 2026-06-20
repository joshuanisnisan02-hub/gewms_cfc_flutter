# Role-based navigation checklist

The production RLS migration makes Water, Electricity, Dashboard totals, and Master Data Admin-only. Before enabling that migration in production, the Flutter app should hide admin-only screens from Driver users.

## Expected navigation

Admin users should see:

1. Dashboard
2. Water
3. Electricity
4. Gas
5. Data

Driver users should see only:

1. Gas

Admin gas access should pass `driverId: null` to `GasTransactionsScreen`. Driver gas access should pass the signed-in profile `driver_id` to `GasTransactionsScreen`.

## Implementation target

Update `_HomeShellState.build` in `lib/main.dart` so it waits for `profile`, builds `pages` and `destinations` based on `isAdmin`, and resets `index` to `0` if the selected index is outside the available pages.

Recommended behavior:

- show a loading indicator while `profile == null`;
- keep Dashboard, Water, Electricity, Gas, and Data for Admins;
- show only Gas for Drivers;
- pass `asInt(profile?['driver_id'])` to the Driver gas screen;
- avoid querying Water, Electricity, Dashboard totals, and Master Data for Driver users.

## Manual test checklist

Admin account:

1. Can sign in.
2. Sees all five navigation tabs.
3. Dashboard loads without RLS errors.
4. Water and Electricity list/add/edit/delete work.
5. Gas shows all transactions.
6. Master Data loads.

Driver account:

1. Can sign in.
2. Sees only the Gas tab.
3. Gas list shows only records matching `profiles.driver_id`.
4. Receipt upload, replace, and delete work only for assigned transactions.
5. Admin-only screens are not visible.

## Release order

1. Merge the import verification workflow.
2. Run the legacy user import and verifier with the real CSV and service-role key.
3. Merge the role-based navigation UI change.
4. Apply the production RLS migration in staging or a copied Supabase project.
5. Test Admin and Driver accounts.
6. Apply production RLS to the live project.
