BEGIN;
SELECT plan(10);

SELECT has_table('ads', 'accounts', 'accounts table should exist');
SELECT has_table('ads', 'campaigns', 'campaigns table should exist');
SELECT has_table('ads', 'ad_groups', 'ad_groups table should exist');
SELECT has_table('ads', 'ads', 'ads table should exist');
SELECT has_table('ads', 'assets', 'assets table should exist');

SELECT has_pk('ads', 'accounts', 'accounts should have a PK');
SELECT has_pk('ads', 'campaigns', 'campaigns should have a PK');
SELECT has_pk('ads', 'ad_groups', 'ad_groups should have a PK');
SELECT has_pk('ads', 'ads', 'ads should have a PK');
SELECT has_pk('ads', 'assets', 'assets should have a PK');

SELECT * FROM finish();
ROLLBACK;
