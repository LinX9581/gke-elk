#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-elk}"

echo "=============================="
echo "  ELK Stack Status"
echo "=============================="
echo ""

# -------- Kibana URL --------
KIBANA_IP="$(kubectl get svc elk-kb-http -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")"
KIBANA_PORT="$(kubectl get svc elk-kb-http -n "$NS" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "5601")"

if [[ -n "$KIBANA_IP" ]]; then
  echo "  Kibana URL:  https://${KIBANA_IP}:${KIBANA_PORT}"
else
  echo "  Kibana URL:  (pending - LoadBalancer IP not yet assigned)"
fi

# -------- Credentials --------
ES_PASSWORD="$(kubectl get secret elk-es-elastic-user -n "$NS" -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d 2>/dev/null || echo "(not found)")"

echo ""
echo "  Username:    elastic"
echo "  Password:    $ES_PASSWORD"

# -------- Resource Status --------
echo ""
echo "=============================="
echo "  Resource Status"
echo "=============================="
echo ""

echo "--- Elasticsearch ---"
kubectl get elasticsearch -n "$NS" 2>/dev/null || echo "  (not found)"

echo ""
echo "--- Kibana ---"
kubectl get kibana -n "$NS" 2>/dev/null || echo "  (not found)"

echo ""
echo "--- Agent ---"
kubectl get agent -n "$NS" 2>/dev/null || echo "  (not found)"

echo ""
echo "--- Pods ---"
kubectl get pods -n "$NS" -o wide 2>/dev/null || echo "  (not found)"
