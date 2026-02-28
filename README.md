# ELK on GKE (ECK Operator)

使用 [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) 部署，專收 **Traefik Access Log**。

## 架構

```
Traefik Pod (stdout) → Elastic Agent (DaemonSet) → Elasticsearch → Kibana
                        只跑在Traefik所在節點           Ingest Pipeline 解析
                                                     ILM 30 天自動刪除
```
Discover 預設檢視格式
```
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
```

## 檔案說明

| 檔案 | 用途 |
|------|------|
| `deploy.sh` | 安裝 ECK Operator + 建 namespace + 預留 IP |
| `manifests/elasticsearch.yaml` | Elasticsearch（1 node, 10Gi） |
| `manifests/kibana.yaml` | Kibana（LoadBalancer） |
| `manifests/agent.yaml` | Elastic Agent DaemonSet（收 Traefik log） |
| `assets/pipeline-traefik.json` | Ingest Pipeline（JSON 解析 + GeoIP + UA） |
| `assets/setup_pipeline.sh` | 部署 Pipeline + Index Template + ILM |
| `assets/setup_kibana.sh` | 建 Data View + Per-Site Saved Search |
| `del.sh` | 刪除 ELK（保留 PVC） |
| `info.sh` | 查看狀態 / 密碼 |

## 部署流程

```bash
# 1. 前置作業（Operator + namespace + IP）
bash deploy.sh

# 2. 部署 manifests（擇一）
# ArgoCD
argocd app create elk \
  --repo https://github.com/LinX9581/gke-elk \
  --path manifests \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace elk --upsert
argocd app sync elk

# 或手動
kubectl apply -f manifests/

# 3. 等 ES Ready 後，部署 Pipeline + ILM
bash assets/setup_pipeline.sh

# 4. 等 Kibana Ready 後，建 Saved Search
bash assets/setup_kibana.sh
```

## 新增網站

編輯 `assets/setup_kibana.sh` 頂部的 `SITES` 陣列，重跑腳本：

```bash
SITES=(
  "nodejs.linx.bar"
  "nodejs-bn.linx.bar"
  "new-site.com"         # ← 加這行
)

bash assets/setup_kibana.sh
```

## 常用查詢 (KQL)

```bash
traefik.host: nodejs.linx.bar                              # 篩特定網站
traefik.host: nodejs.linx.bar and traefik.duration_ms > 500 # 慢請求
traefik.host: nodejs.linx.bar and traefik.status >= 500     # 5xx 錯誤
```

## 管理

```bash
bash info.sh    # 查看狀態 / 密碼
bash del.sh     # 刪除 ELK（保留 PVC）
```

---

> Built with Codex + Claude Code