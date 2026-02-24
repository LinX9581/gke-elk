# ELK on GKE (ECK Operator)

使用 [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) 官方 Operator 部署。

## 檔案說明

| 檔案 | 用途 |
|---|---|
| `bootstrap.sh` | 一鍵安裝（Operator + ES + Kibana + Agent） |
| `elasticsearch.yaml` | Elasticsearch CRD（1 node, 10Gi） |
| `kibana.yaml` | Kibana CRD（LoadBalancer 暴露） |
| `agent.yaml` | Elastic Agent DaemonSet（收 container log） |
| `del.sh` | 刪除 ELK（保留 PVC） |
| `info.sh` | 查看 ELK 狀態 |

## 快速開始

```bash
# 取得IP
bash bootstrap.sh

# ArgoCD 佈署
argocd app create elk \
  --repo https://github.com/LinX9581/gke-elk \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace elk \
  --upsert

argocd app sync elk

# 查看狀態
bash info.sh

# 刪除
bash del.sh
```