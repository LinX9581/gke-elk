#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-nownews-terraform}"
REGION="${REGION:-asia-east1}"
NS="${NS:-elk}"
STATIC_IP_NAME="${STATIC_IP_NAME:-kibana-elk-lb-ip}"

info() { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

command -v kubectl >/dev/null || err "kubectl not found"
command -v helm    >/dev/null || err "helm not found"
command -v gcloud  >/dev/null || err "gcloud not found"

# -------- Step 1: Install ECK Operator --------
info "Step 1/3 — Install ECK Operator"
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo update elastic
helm upgrade --install elastic-operator elastic/eck-operator \
  -n elastic-system --create-namespace --wait

# -------- Step 2: Ensure namespace --------
info "Step 2/3 — Create namespace"
kubectl create namespace "$NS" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl label namespace "$NS" workload=observability --overwrite

# -------- Step 3: Reserve static IP --------
info "Step 3/3 — Reserve static IP"
if gcloud compute addresses describe "$STATIC_IP_NAME" \
     --project "$PROJECT_ID" --region "$REGION" >/dev/null 2>&1; then
  info "Reusing static IP: $STATIC_IP_NAME"
else
  gcloud compute addresses create "$STATIC_IP_NAME" \
    --project "$PROJECT_ID" --region "$REGION"
fi

STATIC_IP="$(gcloud compute addresses describe "$STATIC_IP_NAME" \
  --project "$PROJECT_ID" --region "$REGION" --format='value(address)')"

# -------- Done --------
echo ""
info "=== Prerequisites Ready ==="
echo "  Static IP: $STATIC_IP"
echo ""
echo "  Next: ArgoCD sync or manual deploy"
echo ""
echo "  ArgoCD:"
cat <<'EOF'
    argocd app create elk \
      --repo https://github.com/LinX9581/gke-elk \
      --path manifests \
      --dest-server https://kubernetes.default.svc \
      --dest-namespace elk \
      --upsert

    argocd app sync elk
EOF
echo ""
echo "  Manual (without ArgoCD):"
echo "    kubectl apply -f elasticsearch.yaml"
echo "    kubectl apply -f kibana.yaml"
echo "    kubectl apply -f agent.yaml"
echo ""
echo "  After ES is ready, deploy ingest pipelines:"
echo "    bash setup_pipeline.sh"
echo ""
echo "  After Kibana is ready, create Data View + Saved Search:"
echo "    bash setup_kibana.sh"
