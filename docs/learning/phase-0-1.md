# Learning notes: Phases 0 and 1

What we built, why each piece exists, and things to try yourself. Read it in order: it follows a request from your browser into the cluster, then shows how changes get into the cluster.

## The big picture

How a request reaches the cluster:

```
Browser on Mac: https://argocd.igaming.lab
   │ 1. DNS: dnsmasq answers "*.igaming.lab = 192.168.68.52"
   ▼
Windows desktop :443 ── 2. Windows Firewall allows 80/443
   ▼
k3d load balancer (an nginx container) ── 3. forwards to every node
   ▼
servicelb pods (k3s) ── 4. hostPort 443 → Envoy's Service
   ▼
Envoy proxy ── 5. terminates TLS with the *.igaming.lab certificate (cert-manager)
   │           6. matches the hostname against HTTPRoutes
   ▼
argocd-server Service → Argo CD pod
```

How changes get into the cluster:

```
You: git push ──► GitHub ──► Argo CD notices ──► applies to cluster
                                (Argo CD was installed once by Terraform)
```

## 0. The workstation and the network (Phase 0)

- **Two machines.** The Mac is the workstation: editor, kubectl, Terraform, browser. The Windows desktop (64 GB) runs the cluster. They talk over the LAN.
- **A fixed IP.** The desktop has a DHCP reservation (`192.168.68.52`). The cluster config and the API server's certificate are tied to that address.
- **Windows Firewall.** Inbound 80/443 had to be allowed explicitly. Before that, requests from the Mac timed out. A timeout usually means a firewall drop; a quick refusal means nothing is listening.
- **Wildcard DNS (dnsmasq).** `/etc/hosts` can't do wildcards. dnsmasq on the Mac answers every `*.igaming.lab` name with the desktop's IP. `/etc/resolver/igaming.lab` tells macOS to ask dnsmasq only for that domain, so all other DNS is untouched.
- **kubeconfig.** This file tells kubectl *where* the API server is (`https://192.168.68.52:6444`) and *who you are* (a client certificate with cluster-admin rights). Treat it like a password. It lives in `~/.kube/`, never in git.

Try it:
```bash
dscacheutil -q host -a name anything.igaming.lab   # resolves to 192.168.68.52
kubectl config get-contexts                         # the * marks the active cluster
```

## 1. The cluster (k3d and k3s)

- **What it is.** k3s is a lightweight, fully compliant Kubernetes distribution. k3d runs k3s inside Docker containers, so each "node" is a container on the desktop.
- **Why 4 nodes.** Later phases need real multi-node behaviour: spreading replicas, draining a node, surviving a node loss. One node can't teach that.
- **Server vs agent.** The server runs the control plane: the API server, the scheduler, and the datastore that holds all cluster state. Agents only run workloads.
- **Config as code.** The whole cluster is defined in [infra/k3d/igaming-lab.yaml](../../infra/k3d/igaming-lab.yaml). Recreating it is one command. See [infra/k3d/README.md](../../infra/k3d/README.md).

Try it:
```bash
kubectl get nodes -o wide
kubectl top nodes
```
On the desktop, `docker ps` shows the 4 node containers plus the load balancer.

### Stopping and starting the cluster

On the desktop (PowerShell):

```powershell
k3d cluster stop igaming-lab     # keeps all data
k3d cluster start igaming-lab
```

After a start, from the Mac:

```bash
kubectl get nodes      # wait for 4 x Ready
task status            # apps return to Synced/Healthy
task localstack        # LocalStack lost its in-memory data
```

- **Don't delete.** `k3d cluster delete` wipes everything.
- **No draining needed** when you stop the whole lab. Draining matters when one node leaves while the others keep serving.
- **To free all the RAM:** stop the cluster, quit Docker Desktop, then run `wsl --shutdown`.

## 2. GitOps with Argo CD

- **The idea.** Git holds the *desired state*. A controller inside the cluster keeps making the *actual state* match it. You don't run `kubectl apply`; you push a commit.
- **Why it matters.** Every change is reviewed, auditable and reversible with `git revert`. Configuration drift is corrected automatically.
- **The chicken-and-egg problem.** Argo CD can't install itself from git before it exists. So Terraform installs Argo CD once ([infra/terraform/bootstrap/main.tf](../../infra/terraform/bootstrap/main.tf)), plus one "root" Application. From then on, Argo CD owns everything else. See [ADR 0001](../adr/0001-gitops-bootstrap.md).
- **App-of-apps.** The root app points at [gitops/bootstrap/](../../gitops/bootstrap/), a folder of Application manifests, one per component. Adding a component means adding a file there.
- **Sync waves.** Order matters: CRDs (new resource types such as `Certificate`) must exist before anything uses them.

  | Wave | Contents |
  |---|---|
  | 0 | Controllers and their CRDs |
  | 1 | Things that need those CRDs |
  | 2 | Our cluster config |

- **selfHeal.** If someone changes the cluster by hand, Argo CD reverts it.
- **Server-side diff.** The API server fills in default values that we never wrote. Argo CD compares against what the server *would* store, so those defaults don't look like drift.

Try it. Watch self-heal:
```bash
kubectl -n edge delete httproute https-redirect
kubectl -n edge get httproute -w       # it comes back within seconds; Ctrl+C to stop
```
Then open https://argocd.igaming.lab (user `admin`, password from `task argocd:password`). Click `root` and look at the tree.

## 3. The edge: Gateway API and Envoy Gateway

The edge is where outside traffic enters. In a real company this is Cloudflare plus a cloud load balancer. Three Kubernetes objects split the job ([gateway.yaml](../../gitops/platform/config/gateway.yaml), [routes.yaml](../../gitops/platform/config/routes.yaml)):

| Object | Question it answers | Ours |
|---|---|---|
| **GatewayClass** | Which software implements gateways? | `envoy` → Envoy Gateway |
| **Gateway** | Which ports and TLS? Who may attach routes? | `:80` (redirect only), `:443` for `*.igaming.lab` |
| **HTTPRoute** | Which hostname goes to which Service? | `argocd.igaming.lab` → `argocd-server` |

- **Why Gateway API rather than Ingress.** It is the successor standard, and ingress-nginx is retired. It also separates roles: the platform team owns the Gateway, and app teams own their own HTTPRoutes.
- **Why Traefik is disabled.** Two ingress controllers would fight over ports 80/443.
- **Who owns the CRDs.** k3s installs the Gateway API CRDs. Argo CD installs only Envoy Gateway's own CRDs, so two installers never fight. See [ADR 0002](../adr/0002-edge-and-gateway-api-crds.md).

Try it:
```bash
kubectl get gateway,httproute -A
curl -v http://argocd.igaming.lab 2>&1 | grep -E '< HTTP|< location'   # the 301 redirect
```

## 4. TLS and cert-manager

- **The chain of trust:**
  1. A self-signed issuer creates the **iGaming Lab Root CA**.
  2. The CA signs a **wildcard certificate** for `*.igaming.lab`.
  3. Envoy serves that certificate to clients.

  See [cert-issuers.yaml](../../gitops/platform/config/cert-issuers.yaml) and [wildcard-certificate.yaml](../../gitops/platform/config/wildcard-certificate.yaml).
- **Why `task trust-ca` was needed.** A browser trusts a certificate only if it chains up to a root it already trusts. You added our root to the macOS keychain. In production you'd use a public CA (Let's Encrypt or Cloudflare) instead.
- **Automatic renewal.** cert-manager renews certificates before they expire (ours last 90 days). Expired certificates are a classic production outage.
- **A gotcha we hit.** macOS rejects server certificates without the "server auth" usage, so the certificate sets it explicitly.

Try it:
```bash
kubectl get certificate -A
echo | openssl s_client -connect argocd.igaming.lab:443 -servername argocd.igaming.lab 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

## 5. Secrets: LocalStack and External Secrets

- **The problem.** Apps need passwords. Secrets must never be in git, and plain Kubernetes Secrets are only base64-encoded, not encrypted.
- **The AWS pattern.** Secrets live in **AWS Secrets Manager**. **External Secrets Operator** copies them into Kubernetes Secrets and keeps them in sync, so rotating a value in AWS updates the cluster.
- **Locally, LocalStack plays AWS.** It answers the same API calls, so Terraform and External Secrets work unchanged. It needs a free Hobby-plan token, and it keeps its data in memory.
- **How the pieces connect:**
  1. Terraform ([infra/terraform/localstack/main.tf](../../infra/terraform/localstack/main.tf)) creates the secret `igaming/platform/smoke` in LocalStack.
  2. A `ClusterSecretStore` says how to talk to "AWS".
  3. An `ExternalSecret` says which key goes into which Kubernetes Secret ([secret-store.yaml](../../gitops/platform/config/secret-store.yaml)).
- **Where the bootstrap secrets came from.** The LocalStack token went from `~/.config/igaming-lab/secrets.env` (mode 600), through Terraform, into a Kubernetes Secret. It never touched git.

Try it. Rotate a secret from "AWS" into the cluster:
1. Change the `message` text in `infra/terraform/localstack/main.tf`, then run `task localstack`.
2. Within a minute, check the new value:
   ```bash
   kubectl -n external-secrets get secret platform-smoke -o jsonpath='{.data.message}' | base64 -d
   ```

## 6. Guardrails: namespaces, quotas and policies

- **Application namespaces.** `igaming-staging` and `igaming-prod` will hold our apps ([namespaces.yaml](../../gitops/platform/config/namespaces.yaml)). Each has:
  - a **ResourceQuota**: a total budget, so staging can't starve prod
  - a **LimitRange**: default CPU and memory for containers that don't declare any
  - **Pod Security labels**: Kubernetes' built-in check that blocks dangerous pods (enforce `baseline`, warn on `restricted`)
- **Kyverno** is a policy engine that checks resources as they're created. It runs in **Audit** mode: violations are recorded in **PolicyReports**, but nothing is blocked yet. The rules:
  - the baseline pod-security rules, from the `kyverno-policies` chart
  - pinned image tags only, no `:latest` ([policies.yaml](../../gitops/platform/config/policies.yaml))
  - resource requests and limits required
- **Exceptions as reviewed code.** The k3s load balancer legitimately needs host ports, so it alone is exempted ([policy-exceptions.yaml](../../gitops/platform/config/policy-exceptions.yaml)):
  - narrowly matched by label, for only 3 policies
  - with a written reason and an owner
  - allowed only in the `kyverno` namespace, so teams can't exempt themselves

  The exempted objects show as `skip` in reports, and the failure count stays at 0. A zero baseline means any new failure is a real signal.

Try it. Trigger an audit finding yourself:
```bash
kubectl -n igaming-staging run test --image=nginx:latest
kubectl -n igaming-staging get policyreport -o wide     # after ~10s: disallow-latest-tag fails
kubectl -n igaming-staging delete pod test
```

## Self-check questions

1. Why does Terraform install Argo CD, but Argo CD install cert-manager?
2. You delete the `edge` namespace by hand. What happens, and why?
3. A teammate adds an HTTPRoute for `grafana.igaming.lab`. Which objects must already exist for it to work?
4. The wildcard certificate expires in 90 days. What renews it, and what would break if renewal failed?
5. Why use External Secrets instead of committing a Kubernetes Secret to git?
6. What's the difference between Kyverno's Audit and Enforce modes, and why did we start with Audit?
7. After a LocalStack restart, what breaks, and what is the fix?
