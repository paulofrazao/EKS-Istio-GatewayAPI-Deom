#!/bin/bash
# MTKC POC EKS - Validate Deployment
#
# This script validates the entire deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=== MTKC POC EKS Validation ==="
echo ""

# Test counter
PASSED=0
FAILED=0

run_test() {
  local name="$1"
  local cmd="$2"
  local expected="$3"

  echo -n "Testing ${name}... "
  result=$(eval "$cmd" 2>/dev/null || echo "FAILED")

  if echo "$result" | grep -q "$expected"; then
    echo "PASSED"
    ((PASSED++))
  else
    echo "FAILED"
    echo "  Expected: ${expected}"
    echo "  Got: ${result}"
    ((FAILED++))
  fi
}

# Get ALB DNS from Terraform
echo "Getting ALB DNS name from Terraform..."
cd "${TF_DIR}"
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")

if [ -z "$ALB_DNS" ]; then
  echo "Error: Could not get ALB DNS. Make sure terraform apply was run."
  exit 1
fi

echo "ALB DNS: ${ALB_DNS}"

# Get Internal NLB DNS
echo "Getting Internal NLB DNS..."
INTERNAL_NLB_DNS=$(kubectl get svc -n istio-ingress -l istio.io/gateway-name=mtkc-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
echo "Internal NLB DNS: ${INTERNAL_NLB_DNS:-pending}"
echo ""

# Wait for ALB to be healthy
echo "Waiting for ALB to be ready (30 seconds)..."
sleep 30

echo ""
echo "=== Running Tests ==="
echo ""

# Test 1: Gateway exists
run_test "Gateway exists" \
  "kubectl get gateway mtkc-gateway -n istio-ingress -o name" \
  "gateway.gateway.networking.k8s.io/mtkc-gateway"

# Test 2: HTTPRoutes exist
run_test "HTTPRoutes exist" \
  "kubectl get httproute -A -o name | wc -l | tr -d ' '" \
  "3"

# Test 3: Health responder pods running
run_test "Health responder pods" \
  "kubectl get pods -n gateway-health -l app=health-responder --field-selector=status.phase=Running -o name | wc -l | tr -d ' '" \
  "2"

# Test 4: App1 pods running
run_test "App1 pods running" \
  "kubectl get pods -n sample-apps -l app=sample-app-1 --field-selector=status.phase=Running -o name | wc -l | tr -d ' '" \
  "2"

# Test 5: App2 pods running
run_test "App2 pods running" \
  "kubectl get pods -n sample-apps -l app=sample-app-2 --field-selector=status.phase=Running -o name | wc -l | tr -d ' '" \
  "2"

# Test 6: Internal NLB provisioned
run_test "Internal NLB provisioned" \
  "echo ${INTERNAL_NLB_DNS}" \
  "internal"

# Test 7: ALB provisioned
run_test "ALB provisioned" \
  "echo ${ALB_DNS}" \
  "elb.amazonaws.com"

# Test 8: HTTPS health endpoint via ALB
run_test "HTTPS /healthz/ready (via ALB)" \
  "curl -sk https://${ALB_DNS}/healthz/ready --max-time 10" \
  "ready"

# Test 9: HTTPS app1 endpoint via ALB
run_test "HTTPS /app1 (via ALB)" \
  "curl -sk https://${ALB_DNS}/app1 --max-time 10" \
  "Hello from App 1"

# Test 10: HTTPS app2 endpoint via ALB
run_test "HTTPS /app2 (via ALB)" \
  "curl -sk https://${ALB_DNS}/app2 --max-time 10" \
  "Hello from App 2"

echo ""
echo "=== Validation Summary ==="
echo "Passed: ${PASSED}"
echo "Failed: ${FAILED}"
echo ""

if [ $FAILED -eq 0 ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some tests failed. Please check the deployment."
  exit 1
fi
