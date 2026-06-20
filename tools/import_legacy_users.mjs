#!/usr/bin/env node

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const [, , csvPath] = process.argv;

if (!csvPath) {
  console.error('Usage: node tools/import_legacy_users.mjs path/to/users.csv');
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const defaultPassword = process.env.DEFAULT_PASSWORD;

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable.');
  process.exit(1);
}

if (!defaultPassword) {
  console.error('Missing DEFAULT_PASSWORD environment variable. Set a temporary password for imported users.');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const csv = readFileSync(csvPath, 'utf8');
const rows = parseCsv(csv);

if (rows.length === 0) {
  console.error(`No rows found in ${basename(csvPath)}.`);
  process.exit(1);
}

let created = 0;
let updated = 0;
let skipped = 0;

for (const row of rows) {
  const email = value(row, ['email', 'user_email', 'username']);
  if (!email || !email.includes('@')) {
    console.warn('Skipping row without valid email:', row);
    skipped += 1;
    continue;
  }

  const fullName = value(row, ['full_name', 'name', 'fullname', 'display_name']) ?? email;
  const role = normalizeRole(value(row, ['role', 'user_role', 'type', 'user_type']) ?? 'Admin');
  const driverId = nullableInt(value(row, ['driver_id', 'driverid']));

  const user = await findOrCreateAuthUser(email, fullName, role);
  if (!user) {
    skipped += 1;
    continue;
  }

  const { error: profileError } = await supabase.from('profiles').upsert({
    id: user.id,
    email,
    full_name: fullName,
    role,
    driver_id: driverId,
  }, { onConflict: 'id' });

  if (profileError) {
    console.error(`Failed to upsert profile for ${email}:`, profileError.message);
    skipped += 1;
    continue;
  }

  if (user.wasCreated) created += 1;
  else updated += 1;

  console.log(`${user.wasCreated ? 'Created' : 'Updated'} ${email} as ${role}${driverId ? ` driver_id=${driverId}` : ''}`);
}

console.log(`Done. Created auth users: ${created}. Updated existing users/profiles: ${updated}. Skipped: ${skipped}.`);

async function findOrCreateAuthUser(email, fullName, role) {
  const existing = await findAuthUserByEmail(email);
  if (existing) return { ...existing, wasCreated: false };

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password: defaultPassword,
    email_confirm: true,
    user_metadata: {
      full_name: fullName,
      role,
    },
  });

  if (error) {
    console.error(`Failed to create auth user ${email}:`, error.message);
    return null;
  }

  return { ...data.user, wasCreated: true };
}

async function findAuthUserByEmail(email) {
  let page = 1;
  const perPage = 1000;

  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const found = data.users.find((user) => user.email?.toLowerCase() === email.toLowerCase());
    if (found) return found;
    if (data.users.length < perPage) return null;
    page += 1;
  }
}

function parseCsv(text) {
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return [];

  const headers = splitCsvLine(lines[0]).map((header) => header.trim().toLowerCase());
  return lines.slice(1).map((line) => {
    const values = splitCsvLine(line);
    return Object.fromEntries(headers.map((header, index) => [header, values[index]?.trim() ?? '']));
  });
}

function splitCsvLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === '"' && inQuotes && next === '"') {
      current += '"';
      index += 1;
    } else if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }

  result.push(current);
  return result;
}

function value(row, names) {
  for (const name of names) {
    const raw = row[name];
    if (raw != null && raw.toString().trim() !== '') return raw.toString().trim();
  }
  return null;
}

function normalizeRole(raw) {
  const text = raw.toString().trim().toLowerCase();
  if (text === 'driver') return 'Driver';
  return 'Admin';
}

function nullableInt(raw) {
  if (raw == null || raw.toString().trim() === '') return null;
  const parsed = Number.parseInt(raw.toString(), 10);
  return Number.isNaN(parsed) ? null : parsed;
}
