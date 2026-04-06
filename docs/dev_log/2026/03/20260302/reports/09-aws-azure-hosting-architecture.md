# vbwd Cloud Hosting Architecture: AWS and Azure
## Separation of Backend, fe-admin, and fe-user with SOLID Infrastructure Principles

**Date:** 2026-03-08
**Type:** Infrastructure / DevOps Architecture Report

---

## 1. System Decomposition

vbwd has three independently deployable units. Each has different traffic patterns, security requirements, update frequencies, and scaling needs. Treating them as a monolith on a single server is the first infrastructure mistake to avoid.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         vbwd Platform                               │
│                                                                      │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────────┐ │
│  │   fe-user    │   │   fe-admin   │   │       backend            │ │
│  │  Vue 3 SPA   │   │  Vue 3 SPA   │   │  Flask + PostgreSQL       │ │
│  │  Port 8080   │   │  Port 8081   │   │  + Redis + Gunicorn      │ │
│  │  Public      │   │  Private     │   │  Port 5000               │ │
│  │  High traffic│   │  Low traffic │   │  Internal only           │ │
│  │  CDN-cacheable│  │  No CDN      │   │  Stateful                │ │
│  └──────┬───────┘   └──────┬───────┘   └────────────┬─────────────┘ │
│         │                  │                         │               │
│         └──────────────────┴──────── /api/v1/ ───────┘               │
└─────────────────────────────────────────────────────────────────────┘
```

### Unit characteristics

| Unit | Audience | Traffic | Cacheability | State | Auth required |
|---|---|---|---|---|---|
| fe-user | Public visitors | High, bursty | High (SPA assets) | Stateless | No (public pages) / JWT (member area) |
| fe-admin | Admin staff only | Very low (<100 req/min) | None (no CDN) | Stateless | Always (admin JWT) |
| backend | Internal (proxied from fe-*) | Medium | API responses: short TTL | Stateful (DB, Redis) | Per-endpoint |

### SOLID applied to infrastructure

- **Single Responsibility**: each service runs exactly one thing (Flask, Nginx for fe-user, Nginx for fe-admin, PostgreSQL, Redis)
- **Open/Closed**: adding a plugin = deploying a new backend container or restarting; does not require fe-* rebuild
- **Liskov / Interface Segregation**: fe-admin and fe-user are interchangeable behind a load balancer from the backend's perspective — both speak the same `/api/v1/` contract
- **Dependency Inversion**: backend never imports from fe-*; fe-* depend on the backend API contract, not implementation

---

## 2. AWS Architecture

### 2a. Tier 1 — Simple / Low Budget ($80–200/month)
*For: solo developers, MVPs, staging environments*

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  CloudFront Distribution                                │
│  - fe-user assets → S3 bucket (fe-user-build)          │
│  - /api/* → ALB (bypass cache)                         │
└────────────────────────────┬────────────────────────────┘
                             │
                    ┌────────▼─────────┐
                    │  Application LB  │
                    │  (ALB, t3.micro) │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼──────┐       │    ┌─────────▼──────┐
     │  EC2 t3.small │       │    │  EC2 t3.micro  │
     │  fe-admin     │       │    │  backend       │
     │  (Nginx)      │       │    │  (Gunicorn)    │
     │  :8081        │       │    │  :5000         │
     │  Private SG   │       │    │  Private SG    │
     └───────────────┘       │    └────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │                             │
    ┌─────────▼──────┐           ┌──────────▼──────┐
    │  RDS PostgreSQL│           │ ElastiCache      │
    │  db.t3.micro   │           │ cache.t3.micro   │
    │  (pg 16)       │           │ (Redis 7)        │
    └────────────────┘           └─────────────────┘

S3 Buckets:
  - vbwd-fe-user-{env}      (static assets, public)
  - vbwd-fe-admin-{env}     (static assets, private, OAC)
  - vbwd-uploads-{env}      (user uploads, private)
```

**Key decisions:**
- fe-user SPA goes to **S3 + CloudFront** — zero server cost for static assets, global CDN, scales to millions of requests for $0–5/month
- fe-admin goes to a **small EC2 + Nginx** behind the ALB — not public, no CDN needed, very low traffic
- backend on its own EC2 — isolated security group, no public ingress
- RDS and ElastiCache in private subnets — no internet access ever
- File uploads to S3 via a presigned URL pattern (backend signs, browser uploads directly)

**Security groups:**
```
ALB-SG:          inbound 443 from 0.0.0.0/0
fe-admin-SG:     inbound 8081 from ALB-SG only
backend-SG:      inbound 5000 from ALB-SG only
rds-SG:          inbound 5432 from backend-SG only
redis-SG:        inbound 6379 from backend-SG only
```

**CloudFront behavior rules (in order):**
```
/api/*             → ALB origin, cache: NONE, forward all headers+cookies
/admin/*           → ALB origin (fe-admin EC2), cache: NONE, restricted to VPN IP range
/*                 → S3 origin (fe-user), cache: 24h for *.js/*.css, 0 for index.html
```

---

### 2b. Tier 2 — Production / Scalable ($300–800/month)
*For: live SaaS product, 1k–50k users*

```
Internet
    │
    ▼
┌──────────────────────────────────────────────────────────────┐
│  Route 53                                                    │
│  app.example.com    → CloudFront (fe-user)                  │
│  admin.example.com  → ALB (fe-admin ECS service)            │
│  api.example.com    → ALB (backend ECS service) [internal]  │
└─────────────────────────────────────────────────────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐    ┌────────────────────┐
│  CloudFront     │    │  ALB (HTTPS, ACM)  │
│  + WAF          │    │  private subnets   │
│  fe-user SPA    │    └──────────┬─────────┘
│  S3 origin      │               │
└─────────────────┘    ┌──────────┴──────────────────┐
                       │                             │
              ┌────────▼────────┐         ┌──────────▼───────┐
              │  ECS Fargate    │         │  ECS Fargate      │
              │  fe-admin       │         │  backend          │
              │  Service        │         │  Service          │
              │  1–2 tasks      │         │  2–6 tasks        │
              │  Nginx:8081     │         │  Gunicorn:5000    │
              │  0.25 vCPU      │         │  0.5–1 vCPU       │
              │  512 MB         │         │  1–2 GB           │
              └─────────────────┘         └──────────────────┘
                                                   │
                              ┌────────────────────┼────────────────┐
                              │                    │                │
                   ┌──────────▼──────┐   ┌─────────▼──────┐  ┌─────▼──────┐
                   │  RDS PostgreSQL │   │ ElastiCache     │  │  S3        │
                   │  db.t3.medium   │   │ Cluster         │  │  uploads   │
                   │  Multi-AZ       │   │ Redis 7         │  │  private   │
                   │  Automated BU   │   │ cache.t3.small  │  └────────────┘
                   └─────────────────┘   └────────────────┘
```

**ECS Task definitions:**

```json
// backend task
{
  "family": "vbwd-backend",
  "cpu": "512",
  "memory": "1024",
  "networkMode": "awsvpc",
  "containerDefinitions": [{
    "name": "api",
    "image": "your-ecr.amazonaws.com/vbwd-backend:latest",
    "portMappings": [{ "containerPort": 5000 }],
    "environment": [
      { "name": "FLASK_ENV", "value": "production" }
    ],
    "secrets": [
      { "name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:vbwd/db_url" },
      { "name": "REDIS_URL",    "valueFrom": "arn:aws:secretsmanager:...:vbwd/redis_url" },
      { "name": "JWT_SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:...:vbwd/jwt_secret" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": { "awslogs-group": "/ecs/vbwd-backend", "awslogs-region": "eu-central-1" }
    }
  }]
}
```

```json
// fe-admin task
{
  "family": "vbwd-fe-admin",
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [{
    "name": "fe-admin",
    "image": "your-ecr.amazonaws.com/vbwd-fe-admin:latest",
    "portMappings": [{ "containerPort": 80 }]
  }]
}
```

**Auto Scaling policies:**
- backend: target tracking on ALBRequestCountPerTarget > 500 → scale out; CPU > 70% → scale out
- fe-admin: fixed 1 task (traffic is too low to justify auto-scaling)
- fe-user: no ECS service needed — CloudFront + S3 auto-scales natively

---

### 2c. Tier 3 — Enterprise / High Availability ($1,500–5,000/month)
*For: multi-tenant platform, 100k+ users, SLA requirements*

```
  ┌──────────────────────────────────────────────────────────────┐
  │  Two AZs (eu-central-1a, eu-central-1b)                     │
  │                                                              │
  │  ┌────────────────────┐    ┌────────────────────┐           │
  │  │   EKS Node Group   │    │   EKS Node Group   │           │
  │  │   AZ-a             │    │   AZ-b             │           │
  │  │   m6i.xlarge x2    │    │   m6i.xlarge x2    │           │
  │  │                    │    │                    │           │
  │  │  backend pod x3    │    │  backend pod x3    │           │
  │  │  fe-admin pod x1   │    │  fe-admin pod x1   │           │
  │  └────────────────────┘    └────────────────────┘           │
  │                                                              │
  │  ┌──────────────────────────────────────────────────────┐   │
  │  │  RDS Aurora PostgreSQL Serverless v2 (Multi-AZ)      │   │
  │  │  Auto-scales 0.5–32 ACUs                             │   │
  │  └──────────────────────────────────────────────────────┘   │
  │                                                              │
  │  ┌──────────────────────────────────────────────────────┐   │
  │  │  ElastiCache Serverless Redis                        │   │
  │  │  Auto-scales, Multi-AZ, Backup                       │   │
  │  └──────────────────────────────────────────────────────┘   │
  └──────────────────────────────────────────────────────────────┘
```

**Kubernetes manifests (key excerpts):**

```yaml
# backend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vbwd-backend
  namespace: vbwd
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0        # zero-downtime deploys
  selector:
    matchLabels:
      app: vbwd-backend
  template:
    spec:
      containers:
      - name: api
        image: your-ecr/vbwd-backend:{{ TAG }}
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 5
        envFrom:
        - secretRef:
            name: vbwd-secrets
---
# HorizontalPodAutoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vbwd-backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vbwd-backend
  minReplicas: 2
  maxReplicas: 12
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
---
# fe-admin Deployment (fixed, not auto-scaled)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vbwd-fe-admin
  namespace: vbwd
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: fe-admin
        image: your-ecr/vbwd-fe-admin:{{ TAG }}
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "100m"
            memory: "128Mi"
```

---

### AWS CI/CD Pipeline

```
GitHub Push (main)
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│  GitHub Actions                                              │
│                                                              │
│  Job: build-backend                                          │
│    1. docker build -t vbwd-backend .                         │
│    2. run pytest (unit + integration)                        │
│    3. aws ecr get-login-password | docker login              │
│    4. docker push to ECR                                     │
│    5. aws ecs update-service --force-new-deployment          │
│                                                              │
│  Job: build-fe-user (parallel)                               │
│    1. npm ci && npm run build                                │
│    2. aws s3 sync dist/ s3://vbwd-fe-user-prod/              │
│    3. aws cloudfront create-invalidation --paths "/*"        │
│                                                              │
│  Job: build-fe-admin (parallel)                              │
│    1. npm ci && npm run build                                │
│    2. docker build (Nginx + dist/)                           │
│    3. docker push to ECR                                     │
│    4. aws ecs update-service vbwd-fe-admin                   │
└──────────────────────────────────────────────────────────────┘
```

**Critical: database migrations run as a one-off ECS task BEFORE the backend service update:**
```yaml
- name: Run Alembic migrations
  run: |
    aws ecs run-task \
      --cluster vbwd-prod \
      --task-definition vbwd-migrate \
      --overrides '{"containerOverrides":[{"name":"api","command":["flask","db","upgrade"]}]}' \
      --wait
```

---

## 3. Azure Architecture

### 3a. Tier 1 — Simple / Low Budget (€70–180/month)
*For: MVPs, European operators (GDPR-first)*

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure Front Door (Standard)                                │
│  - fe-user  → Azure Static Web Apps                        │
│  - /admin/* → App Service (fe-admin)                       │
│  - /api/*   → App Service (backend)                        │
└────────────────────────────┬────────────────────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
  ┌────────▼────────┐  ┌─────▼──────┐  ┌──────▼───────────────┐
  │  Static Web App │  │ App Service│  │  App Service          │
  │  fe-user SPA    │  │ fe-admin   │  │  backend (Docker)     │
  │  Free tier      │  │ B1 (€13/mo)│  │  B2s (€30/mo)        │
  │  Global CDN     │  │  Nginx     │  │  Gunicorn             │
  └─────────────────┘  └────────────┘  └──────────────────────┘
                                                │
                              ┌─────────────────┼────────────┐
                              │                 │            │
                  ┌───────────▼──────┐  ┌───────▼───┐  ┌────▼────────┐
                  │  Azure DB for    │  │  Azure    │  │  Blob       │
                  │  PostgreSQL      │  │  Cache    │  │  Storage    │
                  │  Flexible Server │  │  for Redis│  │  (uploads)  │
                  │  Burstable B1ms  │  │  Basic C0 │  │             │
                  │  (€14/mo)        │  │  (€14/mo) │  │             │
                  └──────────────────┘  └───────────┘  └─────────────┘
```

**Azure Static Web Apps for fe-user:**
```yaml
# staticwebapp.config.json
{
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/assets/*", "/api/*"]
  },
  "routes": [
    {
      "route": "/api/*",
      "rewrite": "https://vbwd-backend.azurewebsites.net/api/*"
    }
  ],
  "globalHeaders": {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Cache-Control": "no-store"
  },
  "mimeTypes": {
    ".json": "text/json"
  }
}
```

---

### 3b. Tier 2 — Production / Scalable (€350–900/month)
*For: EU-based live SaaS, GDPR-compliant, low-ops teams*

```
Internet
    │
    ▼
┌──────────────────────────────────────────────────────────────┐
│  Azure Front Door Premium                                    │
│  + WAF Policy                                                │
│  + Custom domains + managed TLS                             │
└───────────────────────────┬──────────────────────────────────┘
                            │
          ┌─────────────────┼──────────────────┐
          │                 │                  │
   ┌──────▼──────┐   ┌──────▼──────┐   ┌───────▼──────────────┐
   │ Static Web  │   │ Container   │   │  Container Apps       │
   │ App (fe-user│   │ App         │   │  Environment          │
   │ Standard)   │   │ (fe-admin)  │   │                       │
   │ Global CDN  │   │ 0.25 vCPU   │   │  backend              │
   │ auto-scale  │   │ 0.5 GB      │   │  min: 2, max: 10      │
   └─────────────┘   └─────────────┘   │  0.5 vCPU / 1 GB     │
                                       │  HTTP scaling rule    │
                                       └──────────────────────┘
                                                │
                          ┌─────────────────────┼──────────────┐
                          │                     │              │
              ┌───────────▼──────┐  ┌───────────▼──┐  ┌───────▼──────┐
              │  Azure DB for    │  │ Azure Cache   │  │ Azure Blob   │
              │  PostgreSQL      │  │ for Redis     │  │ Storage      │
              │  Flexible Server │  │ Standard C1   │  │ + CDN        │
              │  D2s_v3, HA      │  │ (€50/mo)      │  │ (uploads)    │
              │  Geo-backup      │  └───────────────┘  └──────────────┘
              └──────────────────┘
```

**Container Apps scaling rule:**
```json
{
  "name": "vbwd-backend",
  "properties": {
    "template": {
      "containers": [{
        "name": "api",
        "image": "yourregistry.azurecr.io/vbwd-backend:latest",
        "resources": { "cpu": 0.5, "memory": "1Gi" },
        "env": [
          { "name": "FLASK_ENV", "value": "production" },
          { "name": "DATABASE_URL", "secretRef": "db-url" },
          { "name": "REDIS_URL", "secretRef": "redis-url" }
        ]
      }],
      "scale": {
        "minReplicas": 2,
        "maxReplicas": 10,
        "rules": [{
          "name": "http-scaling",
          "http": { "metadata": { "concurrentRequests": "30" } }
        }]
      }
    }
  }
}
```

---

### 3c. Tier 3 — Enterprise / AKS ($1,500–4,000/month)
*For: regulated industries, enterprise clients, NIS2/DORA compliance*

```
┌──────────────────────────────────────────────────────────────────┐
│  AKS Cluster (West Europe + North Europe, Private)               │
│                                                                  │
│  System Node Pool: Standard_D2s_v3 x2 (cluster management)      │
│  User Node Pool:   Standard_D4s_v3 x2–8 (auto-scale)            │
│                                                                  │
│  Namespaces:                                                     │
│  - vbwd-prod    (backend, fe-admin)                              │
│  - monitoring   (Prometheus, Grafana)                            │
│  - ingress      (NGINX Ingress Controller + cert-manager)        │
│                                                                  │
│  Key Vault CSI Driver → mounts secrets as files                  │
│  Azure Policy: deny privileged containers, enforce labels        │
│  Microsoft Defender for Containers: enabled                      │
└──────────────────────────────────────────────────────────────────┘

fe-user: Azure Static Web Apps Enterprise (Premium, global PoPs)
         → not in AKS, keeps separation clean

Database: Azure Database for PostgreSQL Flexible Server
          Zone-redundant HA, geo-redundant backup (EU region pair)

Redis: Azure Cache for Redis Enterprise E10 (cluster mode, AOF persistence)
```

**Ingress config:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vbwd-ingress
  namespace: vbwd-prod
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
spec:
  tls:
  - hosts: [admin.example.com, api.example.com]
    secretName: vbwd-tls
  rules:
  - host: admin.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fe-admin-svc
            port:
              number: 80
  - host: api.example.com
    http:
      paths:
      - path: /api/
        pathType: Prefix
        backend:
          service:
            name: backend-svc
            port:
              number: 5000
```

---

### Azure CI/CD Pipeline (GitHub Actions + Azure)

```yaml
# .github/workflows/deploy.yml
name: vbwd Deploy

on:
  push:
    branches: [main]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_PASSWORD: test }
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: pytest tests/unit/ tests/integration/ -v

  deploy-backend:
    needs: test-backend
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Build and push to ACR
        run: |
          az acr build \
            --registry vbwdregistry \
            --image vbwd-backend:${{ github.sha }} \
            ./vbwd-backend
      - name: Run migrations
        run: |
          az containerapp job start \
            --name vbwd-migrate \
            --resource-group vbwd-prod \
            --image vbwdregistry.azurecr.io/vbwd-backend:${{ github.sha }}
      - name: Update Container App
        run: |
          az containerapp update \
            --name vbwd-backend \
            --resource-group vbwd-prod \
            --image vbwdregistry.azurecr.io/vbwd-backend:${{ github.sha }}

  deploy-fe-user:
    needs: test-backend
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: vbwd-fe-user
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - run: npm ci
      - run: npm run build
      - uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.SWA_TOKEN }}
          action: upload
          app_location: vbwd-fe-user/dist

  deploy-fe-admin:
    needs: test-backend
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: vbwd-fe-admin
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - run: npm ci
      - run: npm run build
      - name: Build and push to ACR
        run: |
          az acr build \
            --registry vbwdregistry \
            --image vbwd-fe-admin:${{ github.sha }} \
            .
      - name: Update Container App
        run: |
          az containerapp update \
            --name vbwd-fe-admin \
            --resource-group vbwd-prod \
            --image vbwdregistry.azurecr.io/vbwd-fe-admin:${{ github.sha }}
```

---

## 4. Separation Principles in Practice

### DNS and Domain Strategy

```
example.com          → CloudFront / Azure Front Door → fe-user SPA
www.example.com      → redirect to example.com
admin.example.com    → ALB / Container App → fe-admin (IP allowlist!)
api.example.com      → ALB / Container App → backend (NOT public)
uploads.example.com  → S3 / Blob CDN (signed URLs only)
```

**Never expose api.example.com publicly.** The API is accessed by:
- fe-user via `example.com/api/` (CloudFront/Front Door rewrites to backend)
- fe-admin via `admin.example.com/api/` (rewrites to backend)
- No direct external access

### Network Isolation (both AWS and Azure)

```
Public Subnet:
  - ALB / Application Gateway
  - NAT Gateway

Private Subnet (App):
  - fe-admin containers
  - backend containers

Private Subnet (Data):
  - PostgreSQL
  - Redis
  - S3 VPC endpoint / Storage private endpoint

Peering:
  - App subnet → Data subnet: yes (port 5432, 6379)
  - Public subnet → App subnet: ALB only
  - No direct Internet → Data subnet (ever)
```

### fe-admin IP Restriction

fe-admin should never be publicly accessible. Enforce at infrastructure level:

**AWS (WAF + CloudFront):**
```json
{
  "Name": "admin-ip-allowlist",
  "Priority": 1,
  "Action": { "Block": {} },
  "Statement": {
    "NotStatement": {
      "Statement": {
        "IPSetReferenceStatement": {
          "ARN": "arn:aws:wafv2:...:ipset/admin-allowed-ips"
        }
      }
    }
  }
}
```

**Azure (Front Door WAF Policy):**
```json
{
  "customRules": [{
    "name": "BlockNonAdminIPs",
    "priority": 100,
    "ruleType": "MatchRule",
    "matchConditions": [{
      "matchVariable": "RemoteAddr",
      "operator": "IPMatch",
      "negateCondition": true,
      "matchValue": ["203.0.113.0/24", "10.0.0.0/8"]
    }],
    "action": "Block"
  }]
}
```

---

## 5. Environment Strategy

Three environments minimum:

```
dev      → local Docker Compose (docker-compose.yaml)
staging  → identical to prod, smaller instances, seeded with test data
prod     → full production infrastructure
```

**Environment promotion flow:**
```
Feature branch → PR → staging deploy (auto) → QA → merge to main → prod deploy (auto)
```

Each environment uses separate:
- S3 buckets / Storage accounts (`vbwd-fe-user-dev`, `vbwd-fe-user-staging`, `vbwd-fe-user-prod`)
- RDS/PostgreSQL instances (never share databases between envs)
- Secrets Manager / Key Vault secrets (`/vbwd/dev/*`, `/vbwd/staging/*`, `/vbwd/prod/*`)
- ECR/ACR image tags (commit SHA, not `latest` in prod)

---

## 6. Database Migration Strategy for Zero-Downtime Deploys

Alembic migrations must be **backwards-compatible** with the current running version of the backend. Technique:

```
Step 1: Deploy migration (additive only — add column, never drop)
        Old backend: ignores new column ✓
        New backend: uses new column ✓

Step 2: Deploy new backend code
        Both old and new backend compatible with schema ✓

Step 3 (next release): Drop old column / index / table if needed
```

**Never** deploy a migration and new backend in the same step. The migration ECS task / Container App Job runs and completes before the new backend containers start.

---

## 7. Cost Comparison Summary

| Scenario | AWS Monthly | Azure Monthly | Notes |
|---|---|---|---|
| Solo dev / MVP | $80–130 | €70–110 | t3.micro EC2 + RDS micro + S3 + CloudFront |
| Small SaaS (1–5k users) | $200–350 | €180–300 | ECS Fargate + RDS small + ElastiCache + CloudFront |
| Production (5–50k users) | $500–900 | €450–800 | ECS/Container Apps, Multi-AZ RDS, Redis Standard |
| Enterprise (50k+ users) | $2,000–5,000 | €1,800–4,500 | EKS/AKS, Aurora/Flex HA, Redis Enterprise |

**AWS advantages:** cheaper egress within AWS (S3 → CloudFront free), richer managed service catalog, more mature ECS tooling.

**Azure advantages:** better GDPR positioning (EU data residency guarantees stronger than AWS), Azure Static Web Apps free tier is generous, Container Apps auto-scale-to-zero saves cost for fe-admin, simpler GitHub Actions integration, Azure AD for fe-admin SSO without extra work.

**Recommendation for vbwd CE targeting EU market:** **Azure Tier 2** is the default recommendation. Reasons: GDPR compliance marketing value, Container Apps scale-to-zero for fe-admin (pays zero when no admin is logged in), Static Web Apps for fe-user (free/near-free CDN), Azure Database for PostgreSQL with geo-redundant backup in EU region pair, and GitHub Actions native integration.

---

## 8. Monitoring and Observability

**AWS stack:**
- CloudWatch Logs (backend, fe-admin container logs)
- CloudWatch Metrics + Alarms (CPU, memory, RDS connections, ALB 5xx rate)
- AWS X-Ray (distributed tracing on Flask routes — add `aws-xray-sdk` to requirements.txt)
- CloudWatch Dashboards (one per service)

**Azure stack:**
- Azure Monitor + Log Analytics Workspace
- Application Insights (Flask: `opencensus-ext-azure`, auto-captures requests, exceptions, dependencies)
- Azure Monitor Alerts (CPU, memory, PostgreSQL connection count, HTTP 5xx rate)
- Azure Managed Grafana (connects to Azure Monitor, visualizes all services)

**Minimum alert set for both platforms:**
```
backend HTTP 5xx rate > 1% over 5 minutes → PagerDuty
RDS/PostgreSQL CPU > 80% over 10 minutes → Slack
Redis memory > 85% → Slack
ALB/Front Door P99 latency > 2s → Slack
Disk on any EC2/node > 80% → PagerDuty
Failed Alembic migration job → PagerDuty (blocks deployment)
```

---

## 9. Security Hardening Checklist

- [ ] All secrets in Secrets Manager (AWS) / Key Vault (Azure) — no `.env` files in production containers
- [ ] Container images scanned: ECR image scanning (AWS) / Defender for Containers (Azure)
- [ ] PostgreSQL: SSL enforced, `require` mode, no public access
- [ ] Redis: AUTH password set, TLS in transit, no public access
- [ ] fe-admin: IP allowlist enforced at WAF layer (not just application layer)
- [ ] S3 / Blob Storage: all buckets private, uploads served via signed URLs (15-minute expiry)
- [ ] ALB / Front Door: HTTPS only, TLS 1.2 minimum, HSTS headers
- [ ] Backend container: runs as non-root user (`USER vbwd`, UID 1000)
- [ ] Network: no 0.0.0.0/0 inbound on any security group except ALB port 443
- [ ] Automated dependency scanning: Dependabot (GitHub) or Snyk on CI
- [ ] Backup: RDS automated daily backup with 7-day retention, cross-region copy for prod
- [ ] Incident response: CloudTrail (AWS) / Activity Log (Azure) — 90-day retention
