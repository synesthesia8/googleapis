# Build and Test

```bash
supabase db reset     # Apply migrations + seed
supabase test db      # pgTAP tests
```

# Rules

- Use Google Ads API terminology for column names (`approval_status` not `status`, `policy_topic_entries` not `policy_topics`)
- JSONB stays camelCase as Google returns it. Postgres columns are snake_case.
- Never edit pushed migrations. Create new ones.
- `entity_ledger` is append-only. Never update rows. Never delete rows.
- Raw tables have one `data` jsonb column. Typed columns are PKs only.
- Bootstrap ledger once per customer after first pull: `SELECT ads_v2.bootstrap_entity_ledger('customer-id');`

# Key Docs

- @docs/sources/ — API findings and data model discoveries
- @docs/decisions/ — Architecture decision records
- @docs/backlog.md — Open issues
