# Contributing

## Making Database Changes

```bash
supabase migration new your_migration_name    # Create migration file
# Write your SQL in the new file
supabase db reset                             # Apply and verify locally
supabase test db                              # Run tests
```

Never edit a migration that's been pushed. Create a new one.

## Running Tests

```bash
supabase test db
```

Tests live in `supabase/tests/`. Each test file is a pgTAP test wrapped in `BEGIN` / `ROLLBACK`.

## Branches and Commits

- Branch from `main`
- Branch names: `feature/thing`, `fix/thing`
- Commit format: `type: description` (e.g. `feat: add pull_report table`, `fix: rename column`)
- One concern per commit
