import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const INGEST_API_KEY = Deno.env.get("INGEST_API_KEY") || ""

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 })

  // ── Auth ───────────────────────────────────────────────────
  const apiKey = req.headers.get("x-api-key")
  if (INGEST_API_KEY && apiKey !== INGEST_API_KEY) return new Response("Forbidden", { status: 403 })

  let payload: Record<string, unknown>
  try { payload = await req.json() }
  catch { return new Response("Invalid JSON", { status: 400 }) }

  const syncId = payload.sync_id as string
  const customerId = payload.customer_id as string
  const resourceType = payload.resource_type as string
  const rows = payload.rows as unknown[]

  if (!syncId || !customerId || !resourceType) return new Response("Missing required fields", { status: 400 })

  // ── Route to RPC ───────────────────────────────────────────
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)

  const rpcMap: Record<string, string> = {
    accounts: "upsert_accounts",
    campaigns: "upsert_campaigns",
    ad_groups: "upsert_ad_groups",
    ads: "upsert_ads",
    assets: "upsert_assets",
    customer_assets: "upsert_customer_assets",
    campaign_assets: "upsert_campaign_assets",
    ad_group_assets: "upsert_ad_group_assets",
    ad_group_ad_asset_view: "upsert_ad_group_ad_asset_view",
    create_sync_run: "create_sync_run",
    finalize: "finalize_sync",
  }

  const rpcName = rpcMap[resourceType]
  if (!rpcName) return new Response(`Unknown: ${resourceType}`, { status: 400 })

  const params = (resourceType === "create_sync_run")
    ? { p_sync_id: syncId, p_customer_id: customerId }
    : (resourceType === "finalize")
    ? { p_customer_id: customerId, p_sync_id: syncId }
    : { p_customer_id: customerId, p_sync_id: syncId, p_rows: rows }

  const { error } = await supabase.schema("ads_v2").rpc(rpcName, params)
  if (error) {
    console.error(`${rpcName} failed:`, error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  return new Response(JSON.stringify({ ok: true, count: rows?.length ?? 0 }), { status: 200 })
})
