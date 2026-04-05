CREATE OR REPLACE FUNCTION ads.upsert_assets(
  p_customer_id text,
  p_sync_id text,
  p_rows jsonb
) RETURNS void AS $$
BEGIN
  INSERT INTO ads.assets (
    asset_id, customer_id, name, asset_type,
    text_content, image_url, image_width, image_height,
    youtube_video_id, sitelink_text, sitelink_desc1, sitelink_desc2,
    callout_text, snippet_header, snippet_values, phone_number,
    global_approval, global_review, global_policy_topics,
    last_checked_at, last_sync_id
  )
  SELECT
    (r->>'assetId')::bigint,
    p_customer_id,
    r->>'name',
    r->>'assetType',
    r->>'textContent',
    r->>'imageUrl',
    (r->>'imageWidth')::int,
    (r->>'imageHeight')::int,
    r->>'youtubeVideoId',
    r->>'sitelinkText',
    r->>'sitelinkDesc1',
    r->>'sitelinkDesc2',
    r->>'calloutText',
    r->>'snippetHeader',
    CASE WHEN jsonb_typeof(r->'snippetValues') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(r->'snippetValues'))
      ELSE NULL
    END,
    r->>'phoneNumber',
    r->>'globalApproval',
    r->>'globalReview',
    CASE WHEN jsonb_typeof(r->'globalPolicyTopics') IN ('array', 'object')
      THEN r->'globalPolicyTopics'
      ELSE NULL
    END,
    now(),
    p_sync_id::uuid
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (asset_id, customer_id)
  DO UPDATE SET
    name = EXCLUDED.name,
    asset_type = EXCLUDED.asset_type,
    text_content = EXCLUDED.text_content,
    image_url = EXCLUDED.image_url,
    image_width = EXCLUDED.image_width,
    image_height = EXCLUDED.image_height,
    youtube_video_id = EXCLUDED.youtube_video_id,
    sitelink_text = EXCLUDED.sitelink_text,
    sitelink_desc1 = EXCLUDED.sitelink_desc1,
    sitelink_desc2 = EXCLUDED.sitelink_desc2,
    callout_text = EXCLUDED.callout_text,
    snippet_header = EXCLUDED.snippet_header,
    snippet_values = EXCLUDED.snippet_values,
    phone_number = EXCLUDED.phone_number,
    global_approval = EXCLUDED.global_approval,
    global_review = EXCLUDED.global_review,
    global_policy_topics = EXCLUDED.global_policy_topics,
    last_checked_at = now(),
    last_sync_id = EXCLUDED.last_sync_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
