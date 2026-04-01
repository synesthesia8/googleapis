-- ASSET LINK trigger
CREATE OR REPLACE FUNCTION ads.track_asset_link_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'approval_status', OLD.approval_status, NEW.approval_status);
  END IF;
  IF OLD.review_status IS DISTINCT FROM NEW.review_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'review_status', OLD.review_status, NEW.review_status);
  END IF;
  IF OLD.primary_status IS DISTINCT FROM NEW.primary_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'primary_status', OLD.primary_status, NEW.primary_status);
  END IF;
  IF OLD.link_status IS DISTINCT FROM NEW.link_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'ASSET_LINK', NEW.id, 'link_status', OLD.link_status, NEW.link_status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_asset_link_changes
  BEFORE UPDATE ON ads.asset_links
  FOR EACH ROW EXECUTE FUNCTION ads.track_asset_link_changes();

-- AD trigger
CREATE OR REPLACE FUNCTION ads.track_ad_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'approval_status', OLD.approval_status, NEW.approval_status);
  END IF;
  IF OLD.review_status IS DISTINCT FROM NEW.review_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'review_status', OLD.review_status, NEW.review_status);
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD', NEW.ad_id, 'status', OLD.status, NEW.status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ad_changes
  BEFORE UPDATE ON ads.ads
  FOR EACH ROW EXECUTE FUNCTION ads.track_ad_changes();

-- AD GROUP trigger
CREATE OR REPLACE FUNCTION ads.track_ad_group_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'AD_GROUP', NEW.ad_group_id, 'status', OLD.status, NEW.status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ad_group_changes
  BEFORE UPDATE ON ads.ad_groups
  FOR EACH ROW EXECUTE FUNCTION ads.track_ad_group_changes();

-- CAMPAIGN trigger
CREATE OR REPLACE FUNCTION ads.track_campaign_changes()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'CAMPAIGN', NEW.campaign_id, 'status', OLD.status, NEW.status);
  END IF;
  IF OLD.serving_status IS DISTINCT FROM NEW.serving_status THEN
    INSERT INTO ads.status_changes (customer_id, entity_type, entity_id, field_name, old_value, new_value)
    VALUES (NEW.customer_id, 'CAMPAIGN', NEW.campaign_id, 'serving_status', OLD.serving_status, NEW.serving_status);
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_campaign_changes
  BEFORE UPDATE ON ads.campaigns
  FOR EACH ROW EXECUTE FUNCTION ads.track_campaign_changes();
