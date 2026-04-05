# ADR-0002: v3 Security Hardening

## Status

Accepted

## Context

v2 has two security problems:

1. The Google Ads Script has the API key and Supabase anon key hardcoded. Anyone with access to the script can see them.
2. The `ads_v2` tables are exposed via PostgREST with no RLS. Anyone with the anon key can read/write directly.

Google Ads Scripts have no secure credential storage (no `PropertiesService`, no `ScriptApp.getOAuthToken()`). But they DO have `Utilities.computeHmacSha256Signature()` — full HMAC-SHA256 signing capability.

## Decision

### HMAC request signing

Replace API key auth with HMAC-SHA256 signing. The shared secret is used to sign requests, never transmitted. Each request includes:

- `X-Timestamp` header — current time, prevents replay attacks (5 minute window)
- `X-Signature` header — HMAC-SHA256 of `timestamp.body` using the shared secret

The Edge Function verifies the signature using the Web Crypto API. The secret lives in the script (unavoidable with Google Ads Scripts) and in Supabase Edge Function secrets.

### verify_jwt = false

The v3 Edge Function disables Supabase's JWT gateway verification. HMAC is the auth layer. No Supabase anon key needed in the script.

### RLS on ads_v2 tables

Row Level Security enabled on all `ads_v2` tables with no policies for `anon` or `authenticated` roles. This blocks all direct REST API access. The Edge Function uses the `service_role` key internally, which bypasses RLS.

### Same tables, new front door

v3 writes to the same `ads_v2` tables as v2. No schema duplication. v2 Edge Function and script remain untouched and functional until v3 is verified.

## Consequences

### What becomes better

- Shared secret never travels over the wire (HMAC vs API key)
- Replay attacks prevented by timestamp validation
- Request tampering prevented by body signing
- Direct table access blocked by RLS
- Anon key removed from the script entirely

### What stays the same

- The secret still exists in the script code (Google Ads Scripts limitation)
- People with MCC admin access can still see the secret
- This is acceptable because those people already have full Google Ads access

### What to watch for

- HMAC secret rotation requires updating both the script and the Edge Function secret
- Clock skew between Google's servers and Supabase could cause false rejections (5 minute window should be generous enough)
