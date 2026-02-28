#!/usr/bin/env bash
# --------------------------------------------------
# 自動建立 Kibana Data View + Saved Search（含預設欄位）
# 用法：bash setup_kibana.sh
#
# - 建立 1 個 "All Sites" Saved Search（全站）
# - 根據 SITES 陣列，自動建立 per-site Saved Search
# - 新增網站只要改 SITES 陣列，重跑腳本即可
# --------------------------------------------------
set -euo pipefail

NS="${NS:-elk}"
ES_NAME="${ES_NAME:-elk}"

# ============================================================
# 🔧 網站清單 — 新增網站只改這裡，然後重跑腳本
# ============================================================
SITES=(
  "nodejs.linx.bar"
  "nodejs-bn.linx.bar"
  # "site-c.com"   ← 新增站點取消註解或加新行
)

info() { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

# -------- 取得連線資訊 --------
ES_PASS="$(kubectl get secret -n "$NS" "${ES_NAME}-es-elastic-user" \
  -o jsonpath='{.data.elastic}' | base64 -d)"

KIBANA_IP="$(kubectl get svc ${ES_NAME}-kb-http -n "$NS" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")"
KIBANA_PORT="$(kubectl get svc ${ES_NAME}-kb-http -n "$NS" \
  -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "5601")"

[[ -z "$KIBANA_IP" ]] && err "Kibana LoadBalancer IP not found. Is Kibana running?"
KIBANA_URL="https://${KIBANA_IP}:${KIBANA_PORT}"

info "Kibana URL: $KIBANA_URL"

# -------- 共用欄位清單 --------
COLUMNS_ARRAY='[
      "traefik.client_ip",
      "traefik.host",
      "traefik.path",
      "traefik.status",
      "traefik.method",
      "traefik.referer",
      "traefik.body_bytes",
      "traefik.user_agent",
      "traefik.duration_ms",
      "traefik.geoip.city_name",
      "traefik.geoip.country_name"
    ]'

# -------- 建立或更新 Saved Search 的函式 --------
create_saved_search() {
  local id="$1"
  local title="$2"
  local kql_query="$3"

  # 組 searchSourceJSON：先建好 inner JSON，再用 python 做 JSON-safe 逸出
  local inner_json
  inner_json=$(printf '{"index":"traefik-access-log","query":{"query":"%s","language":"kuery"},"filter":[]}' "$kql_query")
  local escaped_inner
  escaped_inner=$(echo -n "$inner_json" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])')

  local payload
  payload=$(cat <<ENDJSON
{
  "attributes": {
    "title": "${title}",
    "description": "${title}",
    "columns": ${COLUMNS_ARRAY},
    "sort": [["@timestamp", "desc"]],
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "${escaped_inner}"
    }
  },
  "references": [
    {
      "id": "traefik-access-log",
      "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
      "type": "index-pattern"
    }
  ]
}
ENDJSON
)

  local response
  response=$(curl -s -k -u "elastic:${ES_PASS}" \
    -X POST "${KIBANA_URL}/api/saved_objects/search/${id}" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/dev/null)

  # 如果已存在就更新（Kibana 8.x 回傳 conflict 或 already exists）
  if echo "$response" | grep -qiE "conflict|already exists"; then
    response=$(curl -s -k -u "elastic:${ES_PASS}" \
      -X PUT "${KIBANA_URL}/api/saved_objects/search/${id}" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d "$payload" 2>/dev/null)
  fi

  echo "$response" | grep -q '"id"' \
    && info "  ✓ ${title}" \
    || { echo "$response"; err "  ✗ Failed: ${title}"; }
}

# -------- 1. 建立 Data View --------
info "Creating Data View: traefik-access-log"

DV_RESPONSE=$(curl -s -k -u "elastic:${ES_PASS}" \
  -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
    "data_view": {
      "id": "traefik-access-log",
      "title": "logs-traefik.access-*",
      "name": "Traefik Access Log",
      "timeFieldName": "@timestamp"
    },
    "override": true
  }' 2>/dev/null)

echo "$DV_RESPONSE" | grep -q '"id"' \
  && info "  ✓ Data View created" \
  || { echo "$DV_RESPONSE"; err "  ✗ Failed to create Data View"; }

# -------- 2. 建立 All Sites Saved Search --------
info "Creating Saved Searches..."

create_saved_search \
  "traefik-all-sites" \
  "All Sites Access Log" \
  ""

# -------- 3. 建立 Per-Site Saved Search --------
for site in "${SITES[@]}"; do
  # ID: 把 domain 的點換成底線，例如 site-a.com → site-a_com
  site_id="traefik-${site//./_}"

  create_saved_search \
    "$site_id" \
    "${site} Access Log" \
    "traefik.host: ${site}"
done

echo ""
info "=== Done ==="
echo ""
echo "  開啟 Kibana → Discover → Open"
echo ""
echo "  可用的 Saved Search："
echo "    📄 All Sites Access Log"
for site in "${SITES[@]}"; do
  echo "    📄 ${site} Access Log"
done
echo ""
