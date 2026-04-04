import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const HMAC_SECRET = Deno.env.get("HMAC_SECRET") || ""

async function verifyHmac(timestamp: string, body: string, signature: string): Promise<boolean> {
  if (!HMAC_SECRET) return false

  // Reject if timestamp is more than 5 minutes old
  const age = Math.abs(Date.now() - parseInt(timestamp))
  if (isNaN(age) || age > 300000) return false

  // Compute expected signature
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(HMAC_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  )
  const computed = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(timestamp + "." + body)
  )
  const expected = [...new Uint8Array(computed)]
    .map(b => b.toString(16).padStart(2, "0"))
    .join("")

  return expected === signature
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 })

  // ── HMAC Auth ──────────────────────────────────────────────
  const timestamp = req.headers.get("X-Timestamp")
  const signature = req.headers.get("X-Signature")
  if (!timestamp || !signature) return new Response("Missing auth headers", { status: 401 })

  const body = await req.text()
  const valid = await verifyHmac(timestamp, body, signature)
  if (!valid) {
    // Debug: log first 200 chars of body and the lengths
    console.error(`HMAC mismatch: body length=${body.length}, timestamp=${timestamp}, sig=${signature?.substring(0, 16)}...`)
    return new Response("Invalid signature", { status: 403 })
  }

  // ── Parse payload ──────────────────────────────────────────
  let payload: Record<string, unknown>
  try { payload = JSON.parse(body) }
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
