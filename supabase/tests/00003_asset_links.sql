BEGIN;
SELECT plan(3);

SELECT has_table('ads', 'asset_links', 'asset_links table should exist');
SELECT has_pk('ads', 'asset_links', 'asset_links should have a PK');
SELECT has_index('ads', 'asset_links', 'idx_asset_links_natural_key', 'natural key unique index should exist');

SELECT * FROM finish();
ROLLBACK;
