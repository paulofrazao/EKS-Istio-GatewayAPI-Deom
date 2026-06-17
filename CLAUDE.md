# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Proof-of-Concept demonstrating Kubernetes Gateway API on AWS EKS with Istio Ambient Mesh (no sidecars), exposed through AWS ALB. The core challenge it solves is retrofitting modern Kubernetes networking onto existing AWS ALB/WAF infrastructure.

## Architecture

**4-Layer deployment model:**
1. **Terraform Layer 1** — VPC, subnets, NAT, IGW
2. **Terraform Layer 2** — EKS cluster, IAM, ArgoCD, AWS LB Controller, ALB
3. **ArgoCD Layer 3** — Gateway API CRDs, Istio Ambient mesh, Gateway, HTTPRoutes
4. **ArgoCD Layer 4** — Sample applications (app1, app2, health-responder)

**Traffic flow:** Client → ALB (TLS via ACM) → Internal NLB → Istio Gateway (TLS via self-signed cert) → Pods (mTLS via Ambient mesh)

**Key design decisions:**
- Istio Ambient mode (`istio.io/dataplane-mode: ambient`): mTLS without sidecars
- Gateway creates an Internal NLB; NLB IPs are manually registered into the ALB target group
- Dedicated `/healthz` route required for ALB health probes
- ArgoCD uses App-of-Apps pattern; child apps in `argocd/apps/` are numbered (00-08) to enforce sync order
- Node pools are separated: system taint (`CriticalAddonsOnly`) for infra namespaces, untainted for app workloads

## Deployment Commands

### Prerequisites

```bash
# Required tools: terraform >= 1.0, kubectl, helm 3, jq, dig, aws-cli, curl
aws sts get-caller-identity   # verify AWS credentials
# Ensure credentials have access to both us-east-1 (cluster-a) and us-west-1 (cluster-b)
```

### Full Deployment Sequence

```bash
# 1. Bootstrap S3 remote state backend (run once per environment)
./scripts/setup-backend.sh   # defaults: project=mtkc, env=poc, region=us-east-1

# 2. Provision infrastructure (deploys both clusters in parallel)
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set cluster_a_acm_certificate_arn (us-east-1) and
#                          cluster_b_acm_certificate_arn (us-west-1) for HTTPS
terraform apply

# 3. Configure kubectl for each cluster
$(terraform output -raw cluster_a_get_credentials)
$(terraform output -raw cluster_b_get_credentials)

# 4. Generate self-signed backend TLS certs
./scripts/01-generate-certs.sh           # outputs to certs/ (gitignored)

# 5. Bootstrap TLS secret before ArgoCD deploys Gateway
kubectl create namespace istio-ingress
kubectl create secret tls istio-gateway-tls \
  --cert=certs/server.crt \
  --key=certs/server.key \
  -n istio-ingress

# 6. Deploy ArgoCD app-of-apps
kubectl apply -f argocd/root-app.yaml
kubectl get applications -n argocd -w    # wait for all apps to sync

# 7. Register NLB IPs with ALB target group (run after Gateway is Ready)
./scripts/06-register-nlb-with-alb.sh

# 8. Validate
./scripts/04-validate.sh
ALB_A=$(terraform -chdir=terraform output -raw cluster_a_alb_dns_name)
ALB_B=$(terraform -chdir=terraform output -raw cluster_b_alb_dns_name)
curl -k https://${ALB_A}/healthz/ready   # cluster-a
curl -k https://${ALB_B}/healthz/ready   # cluster-b
```

### Individual Script Usage

```bash
./scripts/setup-backend.sh [project] [env] [region]  # S3 backend bootstrap (run once)
./scripts/01-generate-certs.sh [domain]              # default domain: mtkc-poc.local
./scripts/02-deploy-istio.sh                         # Istio + AWS LB Controller via Helm
./scripts/03-deploy-apps.sh                          # k8s manifests only
./scripts/04-validate.sh                             # 10-point health check
./scripts/05-deploy-argocd.sh                        # ArgoCD Helm install only
./scripts/06-register-nlb-with-alb.sh               # NLB→ALB IP registration
```

### ArgoCD Access

```bash
# cluster-a (switch context first)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 | admin / $(terraform output -raw cluster_a_argocd_password)

# cluster-b (switch context first)
kubectl port-forward svc/argocd-server -n argocd 8081:443
# https://localhost:8081 | admin / $(terraform output -raw cluster_b_argocd_password)
```

### Teardown

```bash
kubectl delete -f argocd/root-app.yaml
sleep 60   # wait for ArgoCD to clean up resources
cd terraform && terraform destroy
```

## Key Configuration

**terraform.tfvars required fields:**
- `cluster_a_acm_certificate_arn` — ACM cert ARN for cluster-a ALB (us-east-1, required for HTTPS)
- `cluster_b_acm_certificate_arn` — ACM cert ARN for cluster-b ALB (us-west-1, required for HTTPS)
- `cluster_a_region` — default `us-east-1`
- `cluster_b_region` — default `us-west-1`
- `project_name` — default `mtkc`

**Namespaces with Ambient mesh label** (`istio.io/dataplane-mode: ambient`):
- `istio-ingress` — Gateway lives here
- `gateway-health` — health-responder
- `sample-apps` — app1, app2
- `api-services`

## Application Endpoints

| Path | Service | Replicas |
|------|---------|----------|
| `/healthz`, `/healthz/ready`, `/healthz/live` | health-responder | 2 |
| `/app1`, `/app1/info`, `/app1/health` | sample-app-1 | 2 |
| `/app2`, `/app2/info`, `/app2/health` | sample-app-2 | 2 |

## Terraform Module Layout

```
terraform/modules/
├── vpc/           — VPC, subnets (public/private), NAT, IGW
├── iam/           — Cluster, node, and LB controller IAM roles (IRSA)
├── eks/           — EKS cluster, system & user node groups, OIDC provider
├── alb/           — ALB, target groups (IP type), HTTP/HTTPS listeners
├── argocd/        — ArgoCD via Helm
├── lb-controller/ — AWS Load Balancer Controller via Helm
└── api-gateway/   — AWS API Gateway (optional, separate ingress path)
```

## LocalStack (Local Development)

**Requirements:** LocalStack Pro (`LOCALSTACK_AUTH_TOKEN` set), `tflocal` (`pip install terraform-local`), `awslocal` (`pip install awscli-local`).

```bash
# One-shot deployment
LOCALSTACK_AUTH_TOKEN=<token> ./scripts/localstack-deploy.sh
```

The script runs `tflocal apply -var-file=terraform.tfvars.localstack`, configures kubectl via `awslocal eks update-kubeconfig`, deploys the ArgoCD app-of-apps, and registers the NLB with the ALB target group.

**Key differences from real AWS (`terraform/terraform.tfvars.localstack`):**
- `region = "us-east-1"` — LocalStack default
- `enable_nat_gateway = false` — not needed locally
- `enable_https = false`, `backend_https_enabled = false` — HTTP only; no ACM cert required
- `argocd_service_type = "ClusterIP"` — access via port-forward
- Single node pool, 1 node

**Access without ALB:**
```bash
kubectl port-forward -n istio-ingress svc/istio-gateway 9080:80
curl http://localhost:9080/healthz/ready
```

**Teardown:**
```bash
kubectl delete -f argocd/root-app.yaml
cd terraform && tflocal destroy -var-file=terraform.tfvars.localstack
```

## NLB–ALB Integration

The Gateway resource creates an Internal NLB via AWS LB Controller annotations. The NLB is not directly internet-facing — its private IPs must be registered as targets in the ALB's target group. `scripts/06-register-nlb-with-alb.sh` automates this: it resolves NLB hostname → IPs via `dig`, registers them, and deregisters stale targets. Re-run this script whenever the Gateway is recreated (NLB IPs can change).
