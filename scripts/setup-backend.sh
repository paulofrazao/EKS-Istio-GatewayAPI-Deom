#!/usr/bin/env bash
# Bootstrap the Terraform S3 backend then (re-)initialise the main workspace.
#
# Run this once before the first `terraform apply`, or whenever you need to
# point a fresh clone at the existing remote state.
#
# Usage:
#   ./scripts/setup-backend.sh [project_name] [environment] [region]
#
# Defaults match terraform.tfvars.example values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${REPO_ROOT}/terraform/bootstrap"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

PROJECT_NAME="${1:-mtkc}"
ENVIRONMENT="${2:-poc}"
REGION="${3:-us-east-1}"

echo "==> Verifying AWS credentials..."
aws sts get-caller-identity --output text --query 'Account' > /dev/null

echo "==> Bootstrapping state bucket (bootstrap workspace has local state)..."
cd "${BOOTSTRAP_DIR}"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="project_name=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="region=${REGION}"

BUCKET=$(terraform output -raw bucket_name)
TABLE=$(terraform output -raw dynamodb_table)
echo ""
echo "  Bucket : ${BUCKET}"
echo "  Table  : ${TABLE}"
echo "  Region : ${REGION}"

echo ""
echo "==> Initialising main workspace with S3 backend..."
cd "${TERRAFORM_DIR}"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="dynamodb_table=${TABLE}" \
  -backend-config="region=${REGION}"

echo ""
echo "Done. Run 'terraform apply' from terraform/ to deploy infrastructure."
echo ""
echo "For future checkouts of this repo, run this script again with the same"
echo "arguments to reconnect to the existing state bucket (no resources will"
echo "be re-created — bootstrap is idempotent)."
