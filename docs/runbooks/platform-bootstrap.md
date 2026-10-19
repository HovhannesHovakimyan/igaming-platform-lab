# Runbook: bootstrap or rebuild the platform

## Prerequisites (Mac)

- `kubectl` context `k3d-igaming-lab` works. See [infra/k3d](../../infra/k3d/README.md).
- `~/.config/igaming-lab/secrets.env` (mode 600) contains `LOCALSTACK_AUTH_TOKEN=...`.
- `*.igaming.lab` resolves to the desktop (dnsmasq).

## Steps

1. Install Argo CD and the root app:
   ```bash
   task bootstrap
   ```
2. Wait for convergence (2–5 minutes):
   ```bash
   kubectl -n argocd wait application/root --for=jsonpath='{.status.health.status}'=Healthy --timeout=600s
   ```
   `platform-config` stays Degraded until step 4. This is expected: the `platform-smoke` ExternalSecret has nothing to read yet.
3. After a cluster rebuild, the CA is new. Trust it on the Mac again:
   ```bash
   task trust-ca
   ```
   Delete the old "iGaming Lab Root CA" from Keychain Access first.
4. Create the AWS resources in LocalStack:
   ```bash
   task localstack
   ```
5. Verify:
   ```bash
   task status                    # all Synced / Healthy
   curl -sI https://argocd.igaming.lab | head -1
   kubectl -n external-secrets get secret platform-smoke -o jsonpath='{.data.message}' | base64 -d
   ```

## After a LocalStack restart

LocalStack keeps state in memory. ExternalSecrets start failing with `SecretSyncedError`.

1. Run `task localstack`.
2. Terraform sees the missing resources and recreates them.
3. External Secrets recovers on its next refresh (1 minute).

## Argo CD login

- URL: https://argocd.igaming.lab
- User: `admin`
- Password: `task argocd:password`
