# Partial S3 backend configuration.
# Bucket, table, and region are supplied at `terraform init` time by
# scripts/setup-backend.sh using -backend-config flags.
# Run that script once to bootstrap the bucket and migrate local state.
terraform {
  backend "s3" {
    key     = "eks-istio-gateway/terraform.tfstate"
    encrypt = true
  }
}
