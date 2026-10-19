# iGaming Platform Lab: Plan

A sample iGaming platform built on a home Kubernetes cluster. The aim is to learn what the iGaming industry needs from a platform and to practise Platform/DevOps engineering on the stack named in the target job description: Kubernetes, AWS, observability, Cloudflare, LDAP/Okta, MySQL, MongoDB, ClickHouse, Snowflake, Metabase, Debezium, NATS JetStream and Kafka/Strimzi.

Status: **Phase 0 done (2026-10-20)**. Next: Phase 1.

### Phase 0 findings

- Cluster: k3d `igaming-lab` with 1 server and 3 agents, k3s v1.37.1, on the Windows desktop (`192.168.68.52`, DHCP-reserved). About 47 GiB RAM and 10 CPUs. See [infra/k3d](../infra/k3d/README.md).
- From the Mac: the API on `:6444` is reachable with valid TLS. Host ports 80/443 reach the cluster once a Windows Firewall rule allows them.
- Traefik is disabled. k3s v1.37 installs the Gateway API CRDs by itself (`helm-install-gateway-api-crd`), so check their version against what Envoy Gateway expects in Phase 1.
- NetworkPolicy should be enforced by k3s's embedded kube-router. Verify in Phase 8.
- HTTPS for `*.igaming.lab` arrives with cert-manager in Phase 1. Name resolution for `*.igaming.lab` on the Mac is still to be set up.

## 1. Decisions

| Item | Decision |
|---|---|
| Cluster host | Existing Kubernetes on a Windows 11 Pro desktop (64 GB RAM). The Mac (M1 Pro, 16 GB) is the workstation and reaches it through kubeconfig. |
| Service language | Go |
| Messaging | NATS JetStream carries real-time service events. Kafka (Strimzi) carries the Debezium CDC → ClickHouse analytics pipeline. |
| Git / CI / CD | GitHub monorepo, GitHub Actions, images in GHCR, Argo CD (GitOps) |
| AWS | LocalStack only, provisioned with Terraform |
| Image architecture | Built for `linux/amd64` in CI, because the desktop is x86 and the Mac is arm64 |

### Local stand-ins for SaaS and cloud services

| Job description | Local substitute | Notes |
|---|---|---|
| AWS | LocalStack (S3, Secrets Manager, SQS, KMS) | No real EKS, IAM or VPC behaviour |
| Cloudflare | Envoy Gateway (Gateway API), rate limiting, Coraza WAF, emulated `CF-IPCountry` header | A Cloudflare Tunnel is optional if a domain is available |
| Coralogix | OpenTelemetry Collector → Prometheus, Loki, Tempo, Grafana | The OTel Collector keeps the backend swappable |
| Okta / LDAP | OpenLDAP → Keycloak (OIDC) | |
| Snowflake | ClickHouse acts as the warehouse | The only real gap |

## 2. Target architecture

```
                 Mac (workstation): kubectl, k9s, Go, Terraform, k6, browser
                                      │  kubeconfig / HTTPS (*.igaming.lab)
┌─────────────────────────────────────▼───────────────────────────────────────────┐
│ Windows desktop: Kubernetes                                                     │
│                                                                                 │
│  EDGE   Envoy Gateway (Gateway API) · rate limits · Coraza WAF · geo-block      │
│         emulation · cert-manager internal CA                                    │
│                                                                                 │
│  APPS   lobby-api ─┬─ player-svc ── MySQL (player_db)                           │
│  (Go)              ├─ wallet-svc ── MySQL (wallet_db: ledger + outbox)          │
│                    │      ▲ seamless-wallet API (HMAC)                          │
│         game-provider-sim ┘   payment-sim (PSP + webhooks)                      │
│         bonus-svc ── MongoDB      risk-svc ── MongoDB                           │
│                                                                                 │
│  EVENTS NATS JetStream (bets, wins, deposits, notifications) ← KEDA autoscaling │
│  CDC    MySQL binlog → Debezium (Kafka Connect) → Kafka (Strimzi) → ClickHouse  │
│  BI     Metabase (GGR, RTP, deposits, bonus cost)                               │
│                                                                                 │
│  OBS    OTel Collector → Prometheus · Loki · Tempo → Grafana, Alertmanager      │
│  IAM    OpenLDAP → Keycloak (OIDC) → Grafana, Argo CD, Metabase, Kafka UI       │
│  PLAT   Argo CD · External Secrets · Kyverno · KEDA · Argo Rollouts ·           │
│         Chaos Mesh · Velero                                                     │
│  AWS    LocalStack: S3 (backups, KYC docs), Secrets Manager, SQS, KMS           │
└─────────────────────────────────────────────────────────────────────────────────┘
   GitHub: monorepo → Actions (test, build amd64, Trivy scan, cosign sign, push to
           GHCR, bump image tag) → Argo CD syncs gitops/
```

### Main data flows

1. **Request path:** player → Envoy Gateway → lobby-api → player-svc / wallet-svc → MySQL
2. **Game round:** game-provider-sim → wallet-svc over the signed seamless-wallet API (bet, then win or rollback)
3. **Event path:** services → NATS JetStream → bonus-svc, risk-svc, lobby WebSocket (live balance)
4. **Analytics path:** MySQL binlog → Debezium → Kafka → ClickHouse → Metabase
5. **Telemetry path:** pods → OTel Collector → Prometheus (metrics), Loki (logs), Tempo (traces) → Grafana

## 3. iGaming domain

| Service | What it simulates | DevOps lesson it creates |
|---|---|---|
| **wallet-svc** | Double-entry ledger with bet, win, rollback, deposit and withdraw. Every request carries an idempotency key. An outbox table is written in the same transaction. | Money correctness, database HA and failover, zero-downtime deploys, outbox and CDC |
| **player-svc** | Registration, login, KYC status, responsible-gambling limits (deposit caps, self-exclusion), jurisdiction checks | PII handling (masking in logs), compliance rules enforced in code |
| **game-provider-sim** | Third-party game studio. Slot rounds pay back about 96% (RTP). It calls the wallet over an HMAC-signed API and retries or rolls back on timeouts. | External integrations, timeouts, retries, circuit breakers |
| **payment-sim** | Payment service provider with async webhooks and random latency and failures | Webhook reliability, dead-letter queues |
| **bonus-svc** | Consumes deposit and bet events, grants bonuses, tracks wagering requirements | Event consumers, consumer lag, KEDA autoscaling |
| **risk-svc** | Rules for bet velocity, large wins and multiple accounts (AML and fraud flags) | Event fan-out, back-pressure |
| **lobby-api** | Player-facing API: game catalogue, WebSocket live balance | Ingress, rate limiting, WAF, traffic spikes |
| **reconciliation CronJob** | Checks ledger sums against balances and MySQL against ClickHouse | Alerting on financial drift, the most important iGaming alert |

### Load scenarios (k6)

- Normal evening traffic
- **Match start:** 10× traffic within 2 minutes
- Bonus campaign launch
- Credential-stuffing or bot attack

### iGaming concerns this lab covers

- **Money integrity:** idempotency, double-entry, rollbacks, reconciliation
- **Bursty traffic:** sporting events and promotions
- **Always on:** no maintenance windows during peak hours
- **Compliance:** audit trail, responsible gambling, KYC/AML, geo-restriction, PII
- **Third parties:** game providers and payment providers fail in their own ways
- **Abuse:** DDoS, credential stuffing, bonus abuse

## 4. Repository layout

```
igaming-platform-lab/
├── README.md
├── Taskfile.yml        # one-command workflows: bootstrap, load, chaos, teardown
├── docs/               # PLAN.md, architecture/, adr/, runbooks/ (one per alert), postmortems/
├── services/           # Go workspace: wallet, player, lobby, bonus, risk, game-provider-sim,
│                       # payment-sim, pkg/ (shared telemetry, NATS, HTTP, idempotency)
├── infra/terraform/    # localstack/ (S3, Secrets Manager, SQS, KMS), bootstrap/ (Argo CD + root app)
├── gitops/             # Argo CD app-of-apps, ordered by sync waves:
│                       # platform/ data/ observability/ identity/ apps/
├── data/               # SQL migrations, ClickHouse tables, Debezium connector configs
├── load/k6/
├── chaos/
└── .github/workflows/  # CI per service (path filters), gitops lint (kubeconform), Terraform plan
```

There are two environments, `staging` and `prod`, as separate namespaces with their own databases. Promotion to prod happens through a pull request that changes the prod values.

## 5. Phases

Each phase ends with a "done when" check and at least one ADR or runbook.

### Phase 0: Foundations and cluster discovery
- On the Mac, install Go, k9s, k6, Trivy, cosign, yq, Task, kustomize and helm (check which are already present).
- Create the GitHub repo.
- Inspect the desktop cluster:
  - Which distribution is it: Docker Desktop, Rancher Desktop, minikube or kind?
  - What version is it, and how many nodes does it have?
  - What StorageClass does it use?
  - Does its CNI enforce NetworkPolicy?
  - Do LoadBalancer services work?
  - Can the Mac reach the API server and the gateway over the LAN (TLS SAN, Windows firewall)?
  - How much RAM does WSL2 get? Set it in `.wslconfig`.
- **Decision gate:** if NetworkPolicy isn't enforced or the cluster isn't reachable from the LAN, either adjust the cluster or run a multi-node kind cluster with Cilium on the desktop.
- *Done when:* `kubectl get nodes` works from the Mac, and a test service answers at `https://echo.igaming.lab`.

### Phase 1: GitOps and platform base
- Terraform creates the LocalStack resources and bootstraps Argo CD.
- Argo CD installs, through app-of-apps:
  - cert-manager (internal CA, trusted on the Mac)
  - Envoy Gateway
  - External Secrets Operator, reading from LocalStack Secrets Manager
  - metrics-server
  - Kyverno baseline policies
  - namespaces with ResourceQuotas
- *Done when:* everything is created from git, with no manual `kubectl apply`.

### Phase 2: Observability before the apps
- Install kube-prometheus-stack, Loki, Tempo, the OTel Collector, and Grafana with dashboards stored as code.
- Route Alertmanager to Discord, Slack or Telegram.
- *Done when:* node, pod and certificate-expiry alerts fire on purpose, and each links to a runbook.

### Phase 3: Core data and messaging
- MySQL with 3 replicas, installed through an operator
- MongoDB as a 3-member replica set
- NATS JetStream as a 3-node cluster
- Database backups to LocalStack S3
- Exporters and dashboards for each system
- *Done when:* killing the MySQL primary recovers automatically, and a backup restores into a scratch namespace.

### Phase 4: Core services and CI/CD
- Build wallet, player, game-provider-sim and lobby, sharing one Helm chart.
- CI pipeline:
  1. lint and test
  2. build an amd64 image
  3. scan with Trivy
  4. sign with cosign (keyless, through GitHub OIDC)
  5. push to GHCR
  6. commit the new image tag to `gitops/`
- Kyverno verifies image signatures.
- *Done when:* a k6 smoke test registers a player, deposits, plays 1,000 spins and the balance reconciles, and one trace spans lobby → wallet → MySQL.

### Phase 5: Event-driven services
- Add bonus, risk and payment-sim.
- Add the JetStream streams and consumers, and the wallet outbox.
- KEDA scales consumers on JetStream lag.
- *Done when:* the match-start spike causes lag, KEDA scales out, the lag drains, and no events are lost.

### Phase 6: Analytics pipeline
- Kafka via Strimzi: 3 brokers in KRaft mode, plus Kafka UI.
- Debezium MySQL connector on Kafka Connect.
- ClickHouse (Altinity operator), consuming through the Kafka table engine and materialized views.
- Metabase dashboards: GGR per jurisdiction, actual vs. theoretical RTP, deposit conversion, bonus cost.
- *Done when:* a freshness SLO (wallet change → ClickHouse in under 60 s) has an alert behind it.

### Phase 7: Identity and access
- OpenLDAP with groups `platform`, `developers`, `analysts` and `support`.
- Keycloak provides SSO for Grafana, Argo CD and Kafka UI. Metabase uses LDAP directly.
- Kubernetes RBAC maps to the groups. Whether the API server can use OIDC depends on the distribution found in Phase 0.
- *Done when:* an analyst can use Metabase but cannot access Argo CD.

### Phase 8: Edge and security
- Rate limits and WAF on Envoy Gateway
- Geo-blocking through the emulated `CF-IPCountry` header
- Default-deny NetworkPolicies (for example, only wallet-svc can reach wallet_db)
- Pod Security Admission set to `restricted`
- Secret rotation through External Secrets
- *Done when:* the k6 bot scenario is throttled while the SLO for legitimate traffic holds.

### Phase 9: Reliability engineering
- SLOs for wallet bet success (99.9%) and p99 latency, with multi-window burn-rate alerts (Sloth or Pyrra)
- Argo Rollouts canary for wallet-svc, with automatic rollback driven by Prometheus analysis
- PodDisruptionBudgets and topology spread constraints
- Velero backups with restore drills
- Chaos Mesh game days, each followed by a written postmortem:
  - a Kafka broker dies
  - MySQL gets slow
  - a NATS node is lost
  - DNS fails
  - a bad deploy goes out
  - a disk fills up
- *Done when:* there are at least 5 postmortems and 10 runbooks.

### Phase 10: Capstone
- Architecture document, ADR index and demo script
- Table mapping each job-description bullet to evidence in this repo

## 6. Resource estimate

With both environments and every component running, the cluster needs about **24–32 GB requested**. Give WSL2 or Docker Desktop about 48 GB. Staging can run with fewer replicas.

## 7. Risks and conventions

- **Unknown Kubernetes distribution on Windows.** It affects NetworkPolicy, LoadBalancer, API-server OIDC and node-lifecycle practice. The Phase 0 decision gate resolves this.
- **LocalStack licensing changed in 2026.** The free tier may need an account auth token. Verify before Phase 1.
- **Avoid Bitnami charts and images** because of the 2025 catalogue changes. **Avoid ingress-nginx** because it is retired; use Gateway API with Envoy Gateway.
- **Versions:** check every chart, image and Go module against its registry when implementing, and pin the latest stable release.
- **Storage:** desktop storage is probably single-disk hostPath, so HA drills are realistic at the pod level but not at the disk level.
- **Disk:** the Mac has about 29 GB free. Heavy workloads run on the desktop.
