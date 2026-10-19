# ADR 0001: Terraform bootstraps Argo CD; Argo CD owns everything else

Status: accepted (2026-10-20)

## Context

Something has to install the GitOps controller before GitOps can work. Options were a shell script, Terraform, or Argo CD managing itself after a one-off `helm install`.

## Decision

`infra/terraform/bootstrap` installs:
- Argo CD (Helm)
- one root Application (via the `argocd-apps` chart) that points at `gitops/bootstrap`
- the few Secrets that must never be in git: the LocalStack token and the LocalStack credentials for External Secrets

Everything else is an Argo CD Application in `gitops/bootstrap`, ordered with sync waves:

| Wave | Contents |
|---|---|
| 0 | CRDs and controllers |
| 1 | Things that need those CRDs |
| 2 | Cluster config in `gitops/platform/config` |

## Consequences

- Rebuilding the cluster takes two commands: `task bootstrap`, then `task localstack`.
- Argo CD upgrades go through Terraform, not GitOps. Moving Argo CD under its own management is a possible later step.
- Sync waves between Applications need a health check for `argoproj.io/Application` in `argocd-cm`. It is set in `values/argocd.yaml`.
- Argo CD uses server-side diff. Client-side diff reported API-server defaults on Gateway API resources and CRDs as drift.
