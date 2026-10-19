# Lab cluster (k3d)

The cluster runs on the Windows desktop (`192.168.68.52`) and is managed from the Mac.

| | |
|---|---|
| Nodes | 1 server + 3 agents |
| Kubernetes | k3s v1.37.1 |
| API | `https://192.168.68.52:6444` |
| Edge | host ports 80/443 → k3d load balancer (Envoy Gateway, installed in Phase 1) |
| Disabled | Traefik |
| kubectl context | `k3d-igaming-lab` |

> Give the desktop a DHCP reservation on the router. If its IP changes, update `igaming-lab.yaml` and recreate the cluster.

## Create (on the desktop)

```powershell
k3d version                      # expect v5.9.x
git clone https://github.com/HovhannesHovakimyan/igaming-platform-lab.git
cd igaming-platform-lab
k3d cluster create --config infra/k3d/igaming-lab.yaml
kubectl get nodes                # 4 nodes, Ready
k3d kubeconfig get igaming-lab > igaming-lab.kubeconfig
```

If ports 80/443 are not reachable from the Mac, allow them in Windows Firewall (admin PowerShell):

```powershell
New-NetFirewallRule -DisplayName "igaming-lab HTTP/HTTPS" -Direction Inbound -Protocol TCP -LocalPort 80,443 -Action Allow -Profile Private
```

## Connect the Mac

Copy `igaming-lab.kubeconfig` to the Mac, then merge it:

```bash
cp ~/.kube/config ~/.kube/config.bak
KUBECONFIG=~/.kube/config:./igaming-lab.kubeconfig kubectl config view --flatten > /tmp/kc && mv /tmp/kc ~/.kube/config
chmod 600 ~/.kube/config
kubectl config use-context k3d-igaming-lab
kubectl get nodes
```

The kubeconfig holds cluster-admin credentials. Don't commit it (it is in `.gitignore`).

## Delete

```powershell
k3d cluster delete igaming-lab
```
