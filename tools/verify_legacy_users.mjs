#!/usr/bin/env node

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const [, , csvPath] = process.argv;

if (!csvPath) {
  console.error('Usage: node tools/verify_legacy_users.mjs path/to/users.csv');
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable.');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const csv = readFileSync(csvPath, 'utf8');
const expectedRows = parseCsv(csv)
  .map(normalizeExpectedRow)
  .filter(Boolean);

if (expectedRows.length === 0) {
  console.error(`No valid expected users found in ${basename(csvPath)}.`);
  process.exit(1);
}

const authUsers = await listAllAuthUsers();
let matched = 0;
let failed = 0;

for (const expected of expectedRows) {
  const authUser = authUsers.find((user) => user.email?.toLowerCase() === expected.email.toLowerCase());

  if (!authUser) {
    failed += 1;
    console.error(`FAIL ${expected.email}: missing Supabase Auth user`);
    continue;
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id,email,full_name,role,driver_id')
    .eq('id', authUser.id)
    .maybeSingle();

  if (profileError) {
    failed += 1;
    console.error(`FAIL ${expected.email}: could not read profile: ${profileError.message}`);
    continue;
  }

  if (!profile) {
    failed += 1;
    console.error(`FAIL ${expected.email}: missing public.profiles row for auth user ${authUser.id}`);
    continue;
  }

  const mismatches = [];
  if (profile.email?.toLowerCase() !== expected.email.toLowerCase()) {
    mismatches.push(`profile.email=${profile.email ?? 'null'}`);
  }
  if (profile.role !== expected.role) {
    mismatches.push(`profile.role=${profile.role ?? 'null'} expected=${expected.role}`);
  }
  if (expected.driverId !== null && Number(profile.driver_id) !== expected.driverId) {
    mismatches.push(`profile.driver_id=${profile.driver_id ?? 'null'} expected=${expected.driverId}`);
  }
  if (expected.role === 'Admin' && profile.driver_id !== null && profile.driver_id !== undefined) {
    mismatches.push(`Admin profile should not require driver_id, found ${profile.driver_id}`);
  }

  if (mismatches.length > 0) {
    failed += 1;
    console.error(`FAIL ${expected.email}: ${mismatches.join('; ')}`);
    continue;
  }

  matched += 1;
  console.log(`OK ${expected.email}: auth user and profile linked as ${expected.role}${expected.driverId ? ` driver_id=${expected.driverId}` : ''}`);
}

console.log(`Verification complete. Matched: ${matched}. Failed: ${failed}. Expected users checked: ${expectedRows.length}.`);

if (failed > 0) process.exit(1);

async function listAllAuthUsers() {
  const users = [];
  let page = 1;
  const perPage = 1000;

  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < perPage) return users;
    page += 1;
  }
}

function normalizeExpectedRow(row) {
  const email = value(row, ['email', 'user_email', 'username']);
  if (!email || !email.includes('@')) return null;

  return {
    email,
    fullName: value(row, ['full_name', 'name', 'fullname', 'display_name']) ?? email,
    role: normalizeRole(value(row, ['role', 'user_role', 'type', 'user_type']) ?? 'Admin'),
    driverId: nullableInt(value(row, ['driver_id', 'driverid'])),
  };
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
