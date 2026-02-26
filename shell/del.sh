#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-elk}"

echo "Deleting ELK stack..."
kubectl delete agent  elk -n "$NS" --ignore-not-found
kubectl delete kibana elk -n "$NS" --ignore-not-found
kubectl delete elasticsearch elk -n "$NS" --ignore-not-found

echo ""
echo "ELK resources deleted. PVCs retained."
echo "  To also delete data:  kubectl delete pvc -l common.k8s.elastic.co/type=elasticsearch -n $NS"
echo "  To remove operator:   helm uninstall elastic-operator -n elastic-system"
echo "  To remove namespace:  kubectl delete ns $NS"
