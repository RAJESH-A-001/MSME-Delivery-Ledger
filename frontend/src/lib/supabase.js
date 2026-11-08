/**
 * src/lib/supabase.js — MSME Delivery & Acceptance Ledger
 *
 * Initialises and exports a singleton Supabase client for use
 * throughout the React application.
 *
 * Environment variables (set in frontend/.env.local):
 *   VITE_SUPABASE_URL      — Project URL (safe to expose — public)
 *   VITE_SUPABASE_ANON_KEY — Anon/publishable key (safe to expose — public)
 *
 * Secret keys (service-role key) must NEVER be used here.
 * They are handled exclusively by the FastAPI backend.
 */

import { createClient } from '@supabase/supabase-js'

// ---------------------------------------------------------------------------
// Environment variable validation
// ---------------------------------------------------------------------------
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl) {
  throw new Error(
    '[Supabase] Missing environment variable: VITE_SUPABASE_URL\n' +
      'Add it to frontend/.env.local and restart the dev server.'
  )
}

if (!supabaseAnonKey) {
  throw new Error(
    '[Supabase] Missing environment variable: VITE_SUPABASE_ANON_KEY\n' +
      'Add it to frontend/.env.local and restart the dev server.'
  )
}

// Validate URL format before passing to the SDK
try {
  new URL(supabaseUrl)
} catch {
  throw new Error(
    `[Supabase] VITE_SUPABASE_URL is not a valid URL: "${supabaseUrl}"`
  )
}

// ---------------------------------------------------------------------------
// Supabase client singleton
// ---------------------------------------------------------------------------
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Persist session in localStorage (browser default)
    persistSession: true,
    // Automatically refresh the access token before expiry
    autoRefreshToken: true,
    // Do not detect the session from the URL hash on every page load
    // (can be enabled when auth redirect flows are implemented)
    detectSessionInUrl: false,
  },
})

export default supabase
