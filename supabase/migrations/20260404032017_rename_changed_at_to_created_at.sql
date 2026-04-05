ALTER TABLE ads_v2.policy_timeline RENAME COLUMN changed_at TO created_at;

-- Recreate indexes that reference changed_at
DROP INDEX IF EXISTS ads_v2.idx_log_time;
DROP INDEX IF EXISTS ads_v2.idx_log_customer;
DROP INDEX IF EXISTS ads_v2.idx_log_disapprovals;
DROP INDEX IF EXISTS ads_v2.idx_log_entity;

CREATE INDEX idx_log_time ON ads_v2.policy_timeline (created_at DESC);
CREATE INDEX idx_log_customer ON ads_v2.policy_timeline (customer_id, created_at DESC);
CREATE INDEX idx_log_disapprovals ON ads_v2.policy_timeline (new_approval_status, created_at DESC)
  WHERE new_approval_status = 'DISAPPROVED';
CREATE INDEX idx_log_entity ON ads_v2.policy_timeline (entity_type, customer_id, asset_id, ad_id, field_type, created_at);
