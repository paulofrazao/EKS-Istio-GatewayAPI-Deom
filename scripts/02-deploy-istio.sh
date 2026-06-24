#!/bin/bash
# MTKC POC EKS - Deploy Istio Ambient Mesh and AWS Load Balancer Controller
#
# Prerequisites:
# - EKS cluster created via Terraform
# - kubectl configured for EKS cluster
# - Helm installed
# - AWS CLI configured

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

# Get values from Terraform output
echo "=== Getting Terraform Outputs ==="
cd "${SCRIPT_DIR}/../terraform"

CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
REGION=$(terraform output -raw 2>/dev/null | grep -A1 'region' | tail -1 || echo "ap-southeast-2")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
LB_CONTROLLER_ROLE_ARN=$(terraform output -raw lb_controller_role_arn 2>/dev/null || echo "")

if [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Could not get cluster name from Terraform. Make sure terraform apply was run."
  exit 1
fi

echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo "VPC ID: ${VPC_ID}"
echo "LB Controller Role ARN: ${LB_CONTROLLER_ROLE_ARN}"

# Configure kubectl
echo ""
echo "=== Configuring kubectl ==="
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

# Verify connection
echo "Verifying cluster connection..."
kubectl cluster-info

# Install AWS Load Balancer Controller
echo ""
echo "=== Installing AWS Load Balancer Controller ==="

# Add Helm repos
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${LB_CONTROLLER_ROLE_ARN}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait

echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s

# Install Istio Ambient Mesh
echo ""
echo "=== Installing Istio Ambient Mesh ==="

# Check if istioctl is installed
if ! command -v istioctl &> /dev/null; then
  echo "istioctl not found. Installing..."
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.2 sh -
  export PATH="$PWD/istio-1.24.2/bin:$PATH"
fi

# Install Istio with ambient profile
istioctl install --set profile=ambient -y

# Wait for Istio components
echo "Waiting for Istio components to be ready..."
kubectl rollout status deployment/istiod -n istio-system --timeout=120s
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=120s

# Install Gateway API CRDs if not present
echo ""
echo "=== Installing Gateway API CRDs ==="
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml || true

# Create namespaces
echo ""
echo "=== Creating Namespaces ==="
kubectl apply -f "${SCRIPT_DIR}/../k8s/namespace.yaml"

# Create TLS secret
echo ""
echo "=== Creating TLS Secret ==="
if [ -f "${CERTS_DIR}/server.crt" ] && [ -f "${CERTS_DIR}/server.key" ]; then
  kubectl create secret tls istio-gateway-tls \
    --cert="${CERTS_DIR}/server.crt" \
    --key="${CERTS_DIR}/server.key" \
    -n istio-ingress \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "TLS secret created successfully"
else
  echo "Warning: Certificate files not found. Run 01-generate-certs.sh first."
  echo "Skipping TLS secret creation..."
fi

# Deploy Gateway
echo ""
echo "=== Deploying Istio Gateway ==="
kubectl apply -f "${SCRIPT_DIR}/../k8s/istio/gateway.yaml"

# Wait for Gateway
echo "Waiting for Gateway to be ready..."
sleep 10
kubectl get gateway -n istio-ingress

echo ""
echo "=== Istio Deployment Complete ==="
echo ""
echo "Next step: Run 03-deploy-apps.sh"
