BEGIN;
SELECT plan(4);

SELECT has_table('ads', 'status_changes', 'status_changes table should exist');
SELECT has_table('ads', 'sync_runs', 'sync_runs table should exist');
SELECT has_index('ads', 'status_changes', 'idx_changes_lookup', 'changes lookup index should exist');
SELECT has_index('ads', 'status_changes', 'idx_changes_entity', 'changes entity index should exist');

SELECT * FROM finish();
ROLLBACK;
