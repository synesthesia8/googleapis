BEGIN;
SELECT plan(1);

SELECT has_schema('ads', 'ads schema should exist');

SELECT * FROM finish();
ROLLBACK;
