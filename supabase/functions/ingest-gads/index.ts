import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const INGEST_API_KEY = Deno.env.get("INGEST_API_KEY") || ""

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 })
  }

  // ── Auth ────────────────────────────────────────────────────
  const apiKey = req.headers.get("x-api-key")
  if (INGEST_API_KEY && apiKey !== INGEST_API_KEY) {
    return new Response("Forbidden", { status: 403 })
  }

  let payload: Record<string, unknown>
  try {
    payload = await req.json()
  } catch {
    return new Response("Invalid JSON", { status: 400 })
  }

  const syncId = payload.sync_id as string
  if (!syncId) return new Response("Missing sync_id", { status: 400 })

  // ── Validate payload ────────────────────────────────────────
  const customerId = payload.customer_id as string
  const resourceType = payload.resource_type as string
  const rows = payload.rows as unknown[]

  if (!customerId || !resourceType || !Array.isArray(rows)) {
    return new Response("Invalid payload: need customer_id, resource_type, rows[]", { status: 400 })
  }

  // ── Route to correct RPC ────────────────────────────────────
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  // Create sync run record (must happen before finalize)
  if (resourceType === "create_sync_run") {
    const { error } = await supabase.schema("ads").rpc("create_sync_run", {
      p_sync_id: syncId,
      p_customer_id: customerId,
    })
    if (error) {
      console.error("create_sync_run failed:", error)
      return new Response(JSON.stringify({ error: error.message }), { status: 500 })
    }
    return new Response(JSON.stringify({ created: true }), { status: 200 })
  }

  // Finalize call (deletion detection + cascade refresh)
  if (resourceType === "finalize") {
    const { error } = await supabase.schema("ads").rpc("finalize_sync", {
      p_customer_id: customerId,
      p_sync_id: syncId,
    })
    if (error) {
      console.error("finalize_sync failed:", error)
      return new Response(JSON.stringify({ error: error.message }), { status: 500 })
    }
    return new Response(JSON.stringify({ finalized: true }), { status: 200 })
  }

  // Map resource_type to RPC function name
  const rpcMap: Record<string, string> = {
    accounts: "upsert_accounts",
    campaigns: "upsert_campaigns",
    ad_groups: "upsert_ad_groups",
    ads: "upsert_ads",
    assets: "upsert_assets",
    asset_links: "upsert_asset_links",
  }

  const rpcName = rpcMap[resourceType]
  if (!rpcName) {
    return new Response(`Unknown resource_type: ${resourceType}`, { status: 400 })
  }

  const { error } = await supabase.schema("ads").rpc(rpcName, {
    p_customer_id: customerId,
    p_sync_id: syncId,
    p_rows: rows,
  })

  if (error) {
    console.error(`RPC ${rpcName} failed:`, error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  return new Response(JSON.stringify({ inserted: rows.length }), { status: 200 })
})
