#!/usr/bin/env bash
# LocalStack end-to-end deployment
# Provisions infrastructure via tflocal and deploys apps via ArgoCD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
REGION="us-east-1"

# ── Prerequisites ──────────────────────────────────────────────────────────────

check_prereqs() {
  local missing=()

  if [[ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]]; then
    echo "ERROR: LOCALSTACK_AUTH_TOKEN is not set (LocalStack Pro required for EKS)"
    exit 1
  fi

  for cmd in tflocal awslocal kubectl helm jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}"
    echo "  tflocal:  pip install terraform-local"
    echo "  awslocal: pip install awscli-local"
    exit 1
  fi

  echo "Checking LocalStack health at ${LOCALSTACK_ENDPOINT}..."
  if ! curl -sf "${LOCALSTACK_ENDPOINT}/_localstack/health" | jq -e '.features.persistence' &>/dev/null; then
    if ! curl -sf "${LOCALSTACK_ENDPOINT}/_localstack/health" &>/dev/null; then
      echo "ERROR: LocalStack is not running at ${LOCALSTACK_ENDPOINT}"
      echo "  Start it with: localstack start"
      exit 1
    fi
  fi
  echo "LocalStack is running."
}

# ── Terraform ──────────────────────────────────────────────────────────────────

deploy_infrastructure() {
  echo ""
  echo "==> Deploying infrastructure with tflocal..."
  cd "${REPO_ROOT}/terraform"

  tflocal init -upgrade
  tflocal apply \
    -var-file=terraform.tfvars.localstack \
    -auto-approve

  CLUSTER_NAME=$(tflocal output -raw eks_cluster_name)
  echo "EKS cluster: ${CLUSTER_NAME}"
}

# ── kubectl ────────────────────────────────────────────────────────────────────

configure_kubectl() {
  echo ""
  echo "==> Configuring kubectl..."
  cd "${REPO_ROOT}/terraform"
  CLUSTER_NAME=$(tflocal output -raw eks_cluster_name)

  awslocal eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${REGION}"

  kubectl cluster-info
}

# ── TLS (optional) ─────────────────────────────────────────────────────────────

setup_tls() {
  # Only needed if you want HTTPS on the Gateway (backend_https_enabled = true).
  # With the default localstack tfvars (HTTP only), you can skip this.
  if kubectl get secret istio-gateway-tls -n istio-ingress &>/dev/null; then
    echo "TLS secret already exists, skipping."
    return
  fi

  if [[ ! -f "${REPO_ROOT}/certs/server.crt" ]]; then
    echo "  Generating self-signed certs..."
    "${SCRIPT_DIR}/01-generate-certs.sh"
  fi

  kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret tls istio-gateway-tls \
    --cert="${REPO_ROOT}/certs/server.crt" \
    --key="${REPO_ROOT}/certs/server.key" \
    -n istio-ingress
}

# ── ArgoCD ─────────────────────────────────────────────────────────────────────

deploy_apps() {
  echo ""
  echo "==> Deploying ArgoCD app-of-apps..."
  kubectl apply -f "${REPO_ROOT}/argocd/root-app.yaml"

  echo "Waiting for ArgoCD apps to be created (up to 5 min)..."
  local deadline=$((SECONDS + 300))
  until kubectl get applications -n argocd 2>/dev/null | grep -q "Synced"; do
    if [[ $SECONDS -ge $deadline ]]; then
      echo "WARNING: Timed out waiting for ArgoCD sync — check 'kubectl get applications -n argocd'"
      return
    fi
    sleep 10
  done
  kubectl get applications -n argocd
}

# ── NLB → ALB registration ─────────────────────────────────────────────────────

register_nlb() {
  echo ""
  echo "==> Registering NLB IPs with ALB target group..."
  # Point AWS CLI commands in the script to LocalStack
  export AWS_ENDPOINT_URL="${LOCALSTACK_ENDPOINT}"
  export AWS_DEFAULT_REGION="${REGION}"
  export AWS_ACCESS_KEY_ID="test"
  export AWS_SECRET_ACCESS_KEY="test"

  "${SCRIPT_DIR}/06-register-nlb-with-alb.sh"
}

# ── Summary ────────────────────────────────────────────────────────────────────

print_summary() {
  cd "${REPO_ROOT}/terraform"
  local alb_dns
  alb_dns=$(tflocal output -raw alb_dns_name 2>/dev/null || echo "N/A")
  local argocd_pass
  argocd_pass=$(tflocal output -raw argocd_admin_password 2>/dev/null || echo "see ArgoCD pod logs")

  echo ""
  echo "════════════════════════════════════════"
  echo "  LocalStack deployment complete"
  echo "════════════════════════════════════════"
  echo ""
  echo "ALB DNS (LocalStack): ${alb_dns}"
  echo ""
  echo "Test endpoints (HTTP):"
  echo "  curl http://${alb_dns}/healthz/ready"
  echo "  curl http://${alb_dns}/app1"
  echo "  curl http://${alb_dns}/app2"
  echo ""
  echo "ArgoCD:"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  URL: https://localhost:8080  user: admin  pass: ${argocd_pass}"
  echo ""
  echo "Gateway direct access (bypass ALB):"
  echo "  kubectl port-forward -n istio-ingress svc/istio-gateway 9080:80"
  echo "  curl http://localhost:9080/healthz/ready"
  echo ""
  echo "Teardown:"
  echo "  kubectl delete -f ${REPO_ROOT}/argocd/root-app.yaml"
  echo "  cd ${REPO_ROOT}/terraform && tflocal destroy -var-file=terraform.tfvars.localstack"
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  check_prereqs
  deploy_infrastructure
  configure_kubectl
  # setup_tls  # Uncomment if backend_https_enabled = true in tfvars
  deploy_apps
  register_nlb
  print_summary
}

main "$@"
