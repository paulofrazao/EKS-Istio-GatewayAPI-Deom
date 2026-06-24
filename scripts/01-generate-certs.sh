#!/bin/bash
# MTKC POC EKS - Generate TLS Certificates for End-to-End TLS
#
# This script generates self-signed TLS certificates for the Istio Gateway backend.
#
# END-TO-END TLS ARCHITECTURE:
# ============================
# 1. Client -> ALB: TLS terminated using ACM certificate (managed by AWS)
# 2. ALB -> Internal NLB -> Istio Gateway: TLS using certificates generated here
# 3. Istio Gateway -> Pods: mTLS handled automatically by Istio Ambient
#
# The certificates generated here are for the BACKEND connection (ALB to Istio Gateway).
# For the FRONTEND (client-facing), use AWS ACM certificates.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
DOMAIN="${1:-mtkc-poc.local}"

echo "=== Generating TLS Certificates for Istio Gateway Backend ==="
echo ""
echo "End-to-End TLS Flow:"
echo "  Client --[TLS/ACM]--> ALB --[TLS/Self-signed]--> NLB --> Istio Gateway --[mTLS]--> Pods"
echo ""
echo "Domain: ${DOMAIN}"
echo "Output directory: ${CERTS_DIR}"

mkdir -p "${CERTS_DIR}"

# Generate CA private key
echo "Generating CA private key..."
openssl genrsa -out "${CERTS_DIR}/ca.key" 4096

# Generate CA certificate
echo "Generating CA certificate..."
openssl req -new -x509 -days 365 -key "${CERTS_DIR}/ca.key" \
  -out "${CERTS_DIR}/ca.crt" \
  -subj "/C=AU/ST=NSW/L=Sydney/O=MTKC POC/CN=MTKC POC CA"

# Generate server private key
echo "Generating server private key..."
openssl genrsa -out "${CERTS_DIR}/server.key" 2048

# Create OpenSSL config for SAN
cat > "${CERTS_DIR}/server.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = AU
ST = NSW
L = Sydney
O = MTKC POC
CN = ${DOMAIN}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = localhost
DNS.4 = mtkc-gateway-istio.istio-ingress.svc.cluster.local
IP.1 = 127.0.0.1
EOF

# Generate server CSR
echo "Generating server CSR..."
openssl req -new -key "${CERTS_DIR}/server.key" \
  -out "${CERTS_DIR}/server.csr" \
  -config "${CERTS_DIR}/server.cnf"

# Sign server certificate with CA
echo "Signing server certificate..."
openssl x509 -req -days 365 \
  -in "${CERTS_DIR}/server.csr" \
  -CA "${CERTS_DIR}/ca.crt" \
  -CAkey "${CERTS_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CERTS_DIR}/server.crt" \
  -extensions req_ext \
  -extfile "${CERTS_DIR}/server.cnf"

# Cleanup
rm -f "${CERTS_DIR}/server.csr" "${CERTS_DIR}/server.cnf" "${CERTS_DIR}/ca.srl"

echo ""
echo "=== Certificates Generated Successfully ==="
echo ""
echo "Files created:"
echo "  CA Certificate:     ${CERTS_DIR}/ca.crt"
echo "  Server Certificate: ${CERTS_DIR}/server.crt"
echo "  Server Key:         ${CERTS_DIR}/server.key"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Create the Kubernetes TLS secret for Istio Gateway:"
echo ""
echo "   kubectl create namespace istio-ingress"
echo "   kubectl create secret tls istio-gateway-tls \\"
echo "     --cert=${CERTS_DIR}/server.crt \\"
echo "     --key=${CERTS_DIR}/server.key \\"
echo "     -n istio-ingress"
echo ""
echo "2. For end-to-end TLS, configure Terraform with:"
echo ""
echo "   enable_https          = true"
echo "   acm_certificate_arn   = \"arn:aws:acm:...\""
echo "   backend_https_enabled = true"
echo ""
echo "3. Then run: ./scripts/02-deploy-istio.sh"
