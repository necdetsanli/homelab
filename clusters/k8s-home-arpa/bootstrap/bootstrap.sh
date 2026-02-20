#!/usr/bin/env bash
# =============================================================================
# Homelab GitOps Bootstrap Script
# Deploys ArgoCD and hands control to the GitOps root Application.
#
# Usage:
#   git clone https://github.com/necdetsanli/homelab.git
#   cd homelab
#   bash clusters/k8s-home-arpa/bootstrap/bootstrap.sh
#
# Prerequisites:
#   - kubectl configured with cluster-admin access
#   - sha256sum available (coreutils)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="${SCRIPT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Homelab GitOps Bootstrap"
echo "=========================================="
echo ""

# Step 0: Pre-flight checks
echo "--- Pre-flight checks ---"

if ! command -v kubectl &>/dev/null; then
  err "kubectl not found in PATH"
  exit 1
fi
log "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client -o yaml | grep gitVersion | head -1)"

if ! kubectl cluster-info &>/dev/null; then
  err "Cannot reach Kubernetes API. Check your kubeconfig."
  exit 1
fi
log "Cluster reachable"

# Step 1: Verify ArgoCD install integrity
echo ""
echo "--- Step 1: Verify ArgoCD install integrity ---"
cd "${BOOTSTRAP}/10-argocd"
if sha256sum -c install.yaml.sha256; then
  log "ArgoCD install.yaml integrity verified"
else
  err "SHA256 verification failed for install.yaml"
  exit 1
fi

# Step 2: Create argocd namespace
echo ""
echo "--- Step 2: Create argocd namespace ---"
kubectl apply -k "${BOOTSTRAP}/00-namespaces"
log "argocd namespace created"

# Step 3: Install ArgoCD
echo ""
echo "--- Step 3: Install ArgoCD ---"
kubectl apply -k "${BOOTSTRAP}/10-argocd"
log "ArgoCD manifests applied"

echo "Waiting for ArgoCD server to be ready (timeout: 300s)..."
if kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s; then
  log "ArgoCD server is ready"
else
  err "ArgoCD server did not become ready within 300s"
  warn "Check: kubectl -n argocd get pods"
  exit 1
fi

# Step 4: Create bootstrap AppProject
echo ""
echo "--- Step 4: Create bootstrap AppProject ---"
kubectl apply -k "${BOOTSTRAP}/20-bootstrap-project"
log "Bootstrap AppProject created"

# Step 5: Create root Application
echo ""
echo "--- Step 5: Create root Application ---"
kubectl apply -k "${BOOTSTRAP}/30-root-app"
log "Root Application created — ArgoCD will now manage all platform components"

# Done
echo ""
echo "=========================================="
echo "  Bootstrap complete!"
echo "=========================================="
echo ""
echo "ArgoCD will now:"
echo "  1. Create platform namespaces (cert-manager, metallb-system, etc.)"
echo "  2. Apply default-deny NetworkPolicies"
echo "  3. Create platform AppProject"
echo "  4. Deploy MetalLB and cert-manager"
echo "  5. Configure MetalLB IP pool (192.168.20.200-250)"
echo ""
echo "Get initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Check sync status:"
echo "  kubectl -n argocd get applications.argoproj.io -o wide"
echo ""
