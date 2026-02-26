#!/usr/bin/env bash
# --------------------------------------------------
# 自動建立 Kibana Data View + Saved Search（含預設欄位）
# 用法：bash setup_kibana.sh
#
# 對應原本 Nginx 的 10 個欄位，換成 Traefik 的欄位名稱
# 重建環境後跑一次即可
# --------------------------------------------------
set -euo pipefail

NS="${NS:-elk}"
ES_NAME="${ES_NAME:-elk}"

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

# -------- 1. 建立 Data View --------
info "Creating Data View: traefik-access-log"

DV_RESPONSE=$(curl -s -k -u "elastic:${ES_PASS}" \
  -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
    "data_view": {
      "id": "traefik-access-log",
      "title": "logs-kubernetes.container_logs-*",
      "name": "Traefik Access Log",
      "timeFieldName": "@timestamp"
    },
    "override": true
  }' 2>/dev/null)

echo "$DV_RESPONSE" | grep -q '"id"' \
  && info "  ✓ Data View created" \
  || { echo "$DV_RESPONSE"; err "  ✗ Failed to create Data View"; }

# -------- 2. 建立 Saved Search（含預設欄位）--------
info "Creating Saved Search: traefik-discover"

# 對應原本 Nginx 的欄位排列順序
# nginx.access.x_forwarded_for  → traefik.client_ip
# nginx.access.url              → traefik.path
# nginx.access.response_code    → traefik.status
# nginx.access.method           → traefik.method
# nginx.access.referrer         → traefik.referer
# nginx.access.body_sent.bytes  → traefik.body_bytes
# nginx.access.agent            → traefik.user_agent
# nginx.access.upstream_resp    → traefik.duration_ms
# nginx.access.geoip.city       → traefik.geoip.city_name
# nginx.access.geoip.country    → traefik.geoip.country_name
# (額外) traefik.host

COLUMNS='[
  {"name":"traefik.client_ip","width":160},
  {"name":"traefik.host","width":160},
  {"name":"traefik.path","width":200},
  {"name":"traefik.status","width":80},
  {"name":"traefik.method","width":80},
  {"name":"traefik.referer","width":200},
  {"name":"traefik.body_bytes","width":100},
  {"name":"traefik.user_agent","width":200},
  {"name":"traefik.duration_ms","width":110},
  {"name":"traefik.geoip.city_name","width":120},
  {"name":"traefik.geoip.country_name","width":120}
]'

SEARCH_PAYLOAD=$(cat <<ENDJSON
{
  "attributes": {
    "title": "Traefik Access Log",
    "description": "Traefik access log with pre-selected fields (like Nginx)",
    "columns": [
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
    ],
    "sort": [["@timestamp", "desc"]],
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"index\":\"traefik-access-log\",\"query\":{\"query\":\"log.file.path : *traefik*\",\"language\":\"kuery\"},\"filter\":[]}"
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

SEARCH_RESPONSE=$(curl -s -k -u "elastic:${ES_PASS}" \
  -X POST "${KIBANA_URL}/api/saved_objects/search/traefik-discover" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d "$SEARCH_PAYLOAD" 2>/dev/null)

# 如果已存在就更新
if echo "$SEARCH_RESPONSE" | grep -q "Saved object.*already exists"; then
  SEARCH_RESPONSE=$(curl -s -k -u "elastic:${ES_PASS}" \
    -X PUT "${KIBANA_URL}/api/saved_objects/search/traefik-discover" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -d "$SEARCH_PAYLOAD" 2>/dev/null)
fi

echo "$SEARCH_RESPONSE" | grep -q '"id"' \
  && info "  ✓ Saved Search created" \
  || { echo "$SEARCH_RESPONSE"; err "  ✗ Failed to create Saved Search"; }

echo ""
info "=== Done ==="
echo ""
echo "  開啟 Kibana → Discover"
echo "  左上角 Data View 下拉選 'Traefik Access Log'"
echo "  或 Open → 選 'Traefik Access Log' saved search"
echo ""
echo "  11 個 columns 已預設載入（對應原 Nginx 欄位）"
