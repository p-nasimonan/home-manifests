# GitHub Copilot Instructions for home-manifests

## Kubernetes Access

- **Always use SSH to access the Kubernetes cluster**: All `kubectl` commands must be executed via `ssh k3s-1` with sudo
- Example: `ssh k3s-1 "sudo kubectl get pods -n fission"`

## Project Structure

- **ArgoCD Applications**: Place application definitions in `argocd-apps/` directory
- **Helm Charts and Values**: Place custom values and charts in `apps/` directory
- **Structure Pattern**:
  - `argocd-apps/<app-name>.yaml` - ArgoCD Application manifest
  - `apps/<app-name>/Chart.yaml` - Helm chart definition (if needed)
  - `apps/<app-name>/values.yaml` - Custom Helm values
  - `apps/<app-name>/*.yaml` - Additional manifests (ingress, etc.)

## Infrastructure Configuration

- **Storage**: Use `storageClass: nfs-client` for all PersistentVolumeClaims
  - NFS Server: `192.168.0.9:/mnt/public/k3s`
- **Ingress**: Use `ingressClassName: cloudflare` for all ingress resources
  - Cloudflare Tunnel is configured for external access
  - Domain: `youkan.uk`
- **Monitoring**: Grafana is deployed in `monitoring` namespace
  - Enable ServiceMonitor/PodMonitor when Prometheus Operator CRDs are available

## Git Repository

- Repository: `https://github.com/p-nasimonan/home-manifests.git`
- Main branch: `main`

## Common Tasks

### Checking ArgoCD Application Status
```bash
ssh k3s-1 "sudo kubectl get application <app-name> -n argocd"
ssh k3s-1 "sudo kubectl describe application <app-name> -n argocd"
```

### Testing Helm Charts Locally
```bash
cd apps/<app-name>
helm dependency update
helm template <app-name> . --namespace <namespace>
helm lint .
```

### Deploying with ArgoCD
```bash
ssh k3s-1 "sudo kubectl apply -f argocd-apps/<app-name>.yaml"
```
