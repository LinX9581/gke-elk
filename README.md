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

## 快速開始

```bash
# 部署
bash bootstrap.sh

# 查看狀態
kubectl get elasticsearch,kibana,agent -n elk

# 取得密碼
kubectl get secret elk-es-elastic-user -n elk -o jsonpath='{.data.elastic}' | base64 -d; echo

# 取得 Kibana URL
kubectl get svc elk-kb-http -n elk

# 刪除
bash del.sh
```

## ArgoCD 部署（選用）

如果要透過 ArgoCD 管理，只需建立**一個 App** 指向此目錄：

```bash
argocd app create elk \
  --repo https://github.com/LinX9581/elk-gke \
  --path elk \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace elk \
  --upsert

argocd app sync elk
```

> **注意：** ECK Operator 需先手動安裝（`bootstrap.sh` Step 1），ArgoCD 只管 CRD manifest。

## 登入

- **帳號：** `elastic`
- **密碼：** 由 ECK 自動產生，見上方取得密碼指令
