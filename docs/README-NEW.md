# Google Ads Monitor

Tracks Google Ads approval status changes across campaigns, ad groups, ads, and assets. Pulls everything hourly, stores raw, logs every transition.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli/getting-started)
- [Docker](https://docs.docker.com/get-docker/) (for local Supabase)
- A Google Ads account with script access

## Setup

### 1. Clone and link to Supabase

```bash
git clone <repo-url>
cd ads-monitor
cp .env.example .env   # Fill in your values
supabase link --project-ref <your-project-ref>
```

### 2. Push migrations

```bash
supabase db push
```

### 3. Deploy the Edge Function

```bash
supabase functions deploy ingest
supabase secrets set --env-file supabase/functions/ingest/.env
```

### 4. Set up the Google Ads Script

1. Open Google Ads → Tools → Bulk actions → Scripts
2. Create a new script
3. Paste the contents of `scripts/pull.js`
4. Update `EDGE_FUNCTION_URL` to your Edge Function URL
5. Update `INGEST_API_KEY` to match the key in your Edge Function secrets
6. Save and authorise

### 5. Bootstrap the ledger

After the first successful pull, run once in the Supabase SQL Editor:

```sql
SELECT ads_v2.bootstrap_entity_ledger('your-customer-id');
```

## Running

**Manual pull:** Run the script from Google Ads → Scripts → Preview

**Scheduled:** Set the script to run hourly in Google Ads → Scripts → Schedule

**Local development:**
```bash
supabase db reset     # Reset local DB with migrations + seed
supabase test db      # Run tests
```

## Testing

```bash
supabase test db
```

## Docs

- [CLAUDE.md](CLAUDE.md) — Build rules for AI-assisted development
- [ARCHITECTURE.md](ARCHITECTURE.md) — How the system works
- [docs/decisions/](docs/decisions/) — Why we made the choices we made
- [docs/sources/](docs/sources/) — What we learned about the Google Ads API
- [docs/backlog.md](docs/backlog.md) — What's next
