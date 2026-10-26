# iGaming Platform Lab

A hands-on lab that builds and operates a sample iGaming platform on Kubernetes, to practise platform engineering the way a real iGaming company needs it.

The application is deliberately small: Go microservices for a wallet, players, a game provider, bonuses, risk and payments. Its job is to create real operational problems such as money integrity, traffic spikes at match start, consumer lag, failovers and bad deploys. The platform around it is the main subject of the lab.

> **Status:** Phase 1 done. See [docs/PLAN.md](docs/PLAN.md) for the architecture, decisions and phased roadmap, and [docs/learning/](docs/learning/) for walkthroughs of each phase.

## Stack

| Area | Technologies |
|---|---|
| Platform | Kubernetes, Argo CD (GitOps), Terraform, LocalStack (AWS), Envoy Gateway |
| Services | Go |
| Messaging | NATS JetStream, Kafka (Strimzi) |
| Data | MySQL, MongoDB, ClickHouse, Debezium (CDC), Metabase |
| Observability | OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Alertmanager |
| Identity & security | Keycloak, OpenLDAP, Kyverno, cert-manager, External Secrets, cosign, Trivy |
| Reliability | KEDA, Argo Rollouts, Chaos Mesh, Velero, k6 |
| CI/CD | GitHub Actions, GHCR |

## Architecture

```
Player → Envoy Gateway → lobby-api → player-svc / wallet-svc → MySQL
game-provider-sim → wallet-svc (seamless wallet API)
services → NATS JetStream → bonus-svc, risk-svc, live balance
MySQL binlog → Debezium → Kafka → ClickHouse → Metabase
everything → OpenTelemetry → Prometheus / Loki / Tempo → Grafana
```

The full diagram and the reasoning behind it are in [docs/PLAN.md](docs/PLAN.md).

## Repository layout (planned)

```
docs/           plan, architecture, ADRs, runbooks, postmortems
services/       Go microservices
infra/          Terraform (LocalStack, Argo CD bootstrap)
gitops/         Argo CD applications: platform, data, observability, identity, apps
data/           SQL migrations, ClickHouse schemas, Debezium connectors
load/           k6 load scenarios
chaos/          Chaos Mesh experiments
```
