# ADR 0002: Envoy Gateway at the edge; k3s owns the Gateway API CRDs

Status: accepted (2026-10-20)

## Context

- ingress-nginx is retired, so the lab uses the Gateway API with Envoy Gateway. The bundled k3s Traefik is disabled.
- k3s v1.37 installs the Gateway API CRDs (v1.6.1, standard channel) through its own `gateway-api-crd` HelmChart.
- Envoy Gateway 1.9.2 bundles the same Gateway API version.

## Decision

- k3s keeps ownership of the Gateway API CRDs.
- Argo CD installs only Envoy Gateway's own CRDs, using `gateway-crds-helm` with `gatewayAPI.enabled=false`.
- The controller chart is installed with `crds.enabled=false`.
- One shared Gateway, `edge/igaming`:
  - terminates TLS for `*.igaming.lab` with a wildcard certificate from the internal CA (cert-manager)
  - redirects HTTP to HTTPS
  - accepts HTTPRoutes from any namespace
- k3s servicelb exposes the Envoy Service on the nodes, and the k3d load balancer maps host ports 80/443 to it.

## Consequences

- Two controllers never fight over the same CRDs.
- Before upgrading k3s or Envoy Gateway, check that the Gateway API version k3s ships is supported by the Envoy Gateway release.
- The servicelb pods in `kube-system` use host ports and capabilities, so they appear as failures in Kyverno's audit reports. They are expected and should be excluded before enforcement (Phase 8).
