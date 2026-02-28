#!/usr/bin/env bash
# --------------------------------------------------
# 將 Ingest Pipeline 部署到 Elasticsearch
# 用法：bash setup_pipeline.sh
#
# 重建環境後執行，或改了 pipeline-traefik.json 後重跑即可更新
# --------------------------------------------------
set -euo pipefail

NS="${NS:-elk}"
ES_NAME="${ES_NAME:-elk}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info() { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

# 取得 ES 密碼
ES_PASS="$(kubectl get secret -n "$NS" "${ES_NAME}-es-elastic-user" \
  -o jsonpath='{.data.elastic}' | base64 -d)"

# ES 內部服務位址
ES_URL="https://${ES_NAME}-es-http.${NS}.svc:9200"

# 等待 ES 就緒
info "Waiting for Elasticsearch to be ready..."
kubectl wait --for=condition=Ready pod -n "$NS" -l elasticsearch.k8s.elastic.co/cluster-name="$ES_NAME" --timeout=120s

# 部署每個 pipeline-*.json
for f in "${SCRIPT_DIR}"/pipeline-*.json; do
  [ -f "$f" ] || continue
  # 檔名 pipeline-traefik.json → pipeline 名稱 traefik-access-log
  basename="$(basename "$f" .json)"           # pipeline-traefik
  pipeline_name="${basename#pipeline-}-access-log"  # traefik-access-log

  info "Deploying pipeline: $pipeline_name (from $f)"
  kubectl exec -n "$NS" "${ES_NAME}-es-default-0" -- \
    curl -s -u "elastic:${ES_PASS}" \
    -X PUT "${ES_URL}/_ingest/pipeline/${pipeline_name}" \
    -k -H 'Content-Type: application/json' \
    -d "$(cat "$f")" | grep -q '"acknowledged":true' \
    && info "  ✓ $pipeline_name deployed" \
    || err "  ✗ Failed to deploy $pipeline_name"
done

# -------- 設定 ILM Policy（30 天自動刪除）--------
info "Creating ILM policy: traefik-access-log-policy (30d retention)..."
kubectl exec -n "$NS" "${ES_NAME}-es-default-0" -- \
  curl -s -u "elastic:${ES_PASS}" \
  -X PUT "${ES_URL}/_ilm/policy/traefik-access-log-policy" \
  -k -H 'Content-Type: application/json' \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_age": "7d",
              "max_primary_shard_size": "10gb"
            }
          }
        },
        "delete": {
          "min_age": "30d",
          "actions": { "delete": {} }
        }
      }
    }
  }' | grep -q '"acknowledged":true' \
  && info "  ✓ ILM policy created (hot 7d rollover, 30d delete)" \
  || info "  ⚠ Could not create ILM policy"

# -------- 設定 index template（rollover + pipeline + ILM 自動套用）--------
info "Creating index template: logs-traefik-access..."
kubectl exec -n "$NS" "${ES_NAME}-es-default-0" -- \
  curl -s -u "elastic:${ES_PASS}" \
  -X PUT "${ES_URL}/_index_template/logs-traefik-access" \
  -k -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["logs-traefik.access-*"],
    "template": {
      "settings": {
        "index.default_pipeline": "traefik-access-log",
        "index.lifecycle.name": "traefik-access-log-policy"
      }
    },
    "priority": 500
  }' | grep -q '"acknowledged":true' \
  && info "  ✓ index template created" \
  || info "  ⚠ Could not create index template"

# 也套用到目前已存在的 index（template 只影響新建的）
info "Applying settings to existing index..."
kubectl exec -n "$NS" "${ES_NAME}-es-default-0" -- \
  curl -s -u "elastic:${ES_PASS}" \
  -X PUT "${ES_URL}/logs-traefik.access-default/_settings" \
  -k -H 'Content-Type: application/json' \
  -d '{
    "index.default_pipeline": "traefik-access-log",
    "index.lifecycle.name": "traefik-access-log-policy"
  }' | grep -q '"acknowledged":true' \
  && info "  ✓ existing index updated" \
  || info "  ⚠ No existing index yet (will be created with template)"

info "All pipelines deployed."
