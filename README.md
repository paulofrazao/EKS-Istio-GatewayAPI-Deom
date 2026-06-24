# POC - AWS EKS with Kubernetes Gateway API & Istio Ambient

This POC demonstrates how to implement Kubernetes Gateway API on AWS EKS with Istio Ambient Mesh, exposed via AWS Application Load Balancer (ALB).

In the real world, you don't always get a greenfield opportunity to design the cleanest architecture. More often, you need to retrofit the best possible solution to existing standards and platforms. This project examines exactly that situation—where Kubernetes-hosted workloads need to be exposed via an existing platform with Load Balancers and WAF (or a WAF sandwich architecture).

## Key Features

| Feature | Description |
|---------|-------------|
| **Kubernetes Gateway API** | Future-proof networking replacing deprecated Ingress-NGINX (retiring March 2026) |
| **Istio Ambient Mesh** | Service mesh without sidecars—lower overhead, simplified operations |
| **AWS ALB + Internal NLB** | Leverage existing ALB/WAF infrastructure for secure internet exposure |
| **ArgoCD GitOps** | Declarative, version-controlled Kubernetes customisations and deployments |
| **Separated Node Pools** | System nodes for critical add-ons, User nodes for application workloads |
| **Layered Architecture** | Clear separation: Cloud foundations → EKS setup → K8s customisations → Applications |

## Architecture Overview

![Architecture Overview](docs/images/architecture-overview.png)

> **Note:** The diagram shows "Public Subnet" and "Private Subnet" as single boxes for simplicity, but the actual implementation creates **multiple subnets across Availability Zones** (default: 2 AZs) for high availability.

## End-to-End Traffic Flow

The architecture implements **dual TLS termination** for secure traffic from client to backend:

```mermaid
sequenceDiagram
    participant Client
    participant ALB as AWS ALB<br/>(Public)
    participant NLB as Internal NLB<br/>(Private)
    participant Gateway as Istio Gateway<br/>(Pod)
    participant App as Backend App<br/>(Pod)

    Note over Client,ALB: TLS Session 1 (Frontend)
    Client->>+ALB: HTTPS :443<br/>TLS with ACM Certificate
    ALB->>ALB: TLS Termination

    Note over ALB,Gateway: TLS Session 2 (Backend)
    ALB->>+NLB: HTTPS :443<br/>Re-encrypted
    NLB->>+Gateway: HTTPS :443<br/>TLS Passthrough
    Gateway->>Gateway: TLS Termination<br/>(istio-gateway-tls secret)

    Note over Gateway,App: Plain HTTP (mTLS via Ambient)
    Gateway->>+App: HTTP :8080<br/>Istio Ambient mTLS
    App-->>-Gateway: Response
    Gateway-->>-NLB: Response
    NLB-->>-ALB: Response
    ALB-->>-Client: HTTPS Response
```

### TLS Certificate Chain

| Component | Certificate | Purpose |
|-----------|-------------|---------|
| **ALB Frontend** | ACM Certificate | Terminates client HTTPS, provides trusted certificate |
| **Istio Gateway** | `istio-gateway-tls` Secret | Terminates re-encrypted traffic from ALB via NLB |
| **Pod-to-Pod** | Istio Ambient mTLS | Automatic mTLS between services (no sidecar needed) |

### Certificate Configuration

**1. ALB Frontend (ACM Certificate)**
- Use AWS Certificate Manager (ACM) for the public-facing certificate
- Set `enable_https = true` and `acm_certificate_arn` in Terraform variables

**2. Istio Gateway Backend (Self-signed)**
```bash
# Generate certificates
./scripts/01-generate-certs.sh

# Create Kubernetes secret
kubectl create namespace istio-ingress
kubectl create secret tls istio-gateway-tls \
  --cert=certs/server.crt \
  --key=certs/server.key \
  -n istio-ingress
```

**3. Enable End-to-End TLS in Terraform**
```hcl
# terraform.tfvars
enable_https          = true
acm_certificate_arn   = "arn:aws:acm:region:account:certificate/xxx"
backend_https_enabled = true  # ALB -> NLB -> Gateway over HTTPS
```

## Architecture Layers

![Architecture Layers](docs/images/architecture-layers.png)

## Layer Responsibilities

| Layer | Tool | What It Creates |
|-------|------|-----------------|
| **Layer 1** | Terraform | VPC, Subnets (Public/Private), NAT/IGW, Route Tables |
| **Layer 2** | Terraform | EKS, Node Groups (System/User), IAM, ArgoCD, LB Controller, ALB |
| **Layer 3** | ArgoCD | Gateway API CRDs, Istio Ambient, Gateway, HTTPRoutes |
| **Layer 4** | ArgoCD | Applications (app1, app2, health-responder) |

## EKS Cluster Detail

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'fontSize': '16px'}, 'flowchart': {'nodeSpacing': 50, 'rankSpacing': 80, 'padding': 30}}}%%
flowchart TB
    subgraph EKS["EKS Cluster"]
        subgraph SystemPool["System Node Pool<br/>(Taint: CriticalAddonsOnly)"]
            subgraph KS["kube-system"]
                LBC2[aws-lb-controller]
                CoreDNS[coredns]
                KubeProxy[kube-proxy]
            end
            subgraph IS["istio-system"]
                Istiod2[istiod]
                CNI[istio-cni<br/>DaemonSet]
                ZT[ztunnel<br/>DaemonSet]
            end
            subgraph II["istio-ingress"]
                GW2[mtkc-gateway]
            end
            subgraph AC["argocd"]
                ArgoServer[argocd-server]
            end
        end

        subgraph UserPool["User Node Pool<br/>(No Taint)"]
            subgraph SA["sample-apps"]
                App1B[sample-app-1]
                App2B[sample-app-2]
            end
            subgraph GH["gateway-health"]
                HealthResp[health-responder]
            end
        end
    end

    Note["Note: DaemonSets (istio-cni, ztunnel)<br/>run on ALL nodes with tolerations"]

    style EKS fill:#f0f0f0
    style SystemPool fill:#ffffff
    style UserPool fill:#ffffff
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl
- Helm 3
- jq and dig (for post-deployment script)

## Deployment Steps

### Step 1: Deploy Infrastructure (Layers 1 & 2)

```bash
cd terraform

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed

# Initialize and apply
terraform init
terraform apply
```

This creates:
- **Layer 1:** VPC, subnets, NAT gateway
- **Layer 2:** EKS cluster, ArgoCD, AWS LB Controller, ALB

### Step 2: Configure kubectl

```bash
# Get credentials
$(terraform output -raw eks_get_credentials_command)
```

### Step 3: Generate TLS Certificates

```bash
./scripts/01-generate-certs.sh
```

### Step 4: Create TLS Secret

```bash
kubectl create namespace istio-ingress
kubectl create secret tls istio-gateway-tls \
  --cert=certs/server.crt \
  --key=certs/server.key \
  -n istio-ingress
```

### Step 5: Deploy ArgoCD Root App (Layers 3 & 4)

```bash
# Get ArgoCD admin password
terraform output -raw argocd_admin_password

# Apply root application
kubectl apply -f argocd/root-app.yaml

# Wait for all apps to sync
kubectl get applications -n argocd -w
```

This deploys via ArgoCD:
- **Layer 3:** Gateway API CRDs, Istio Ambient, Gateway, HTTPRoutes
- **Layer 4:** Sample apps

### Step 6: Register NLB with ALB Target Group

```bash
./scripts/06-register-nlb-with-alb.sh
```

> **Why is this step needed?**
>
> The Istio Gateway (via Gateway API) creates an Internal NLB dynamically using the AWS Load Balancer Controller. This happens **after** Terraform completes, when ArgoCD syncs the Gateway resource. Since Terraform doesn't know about this dynamically-created NLB, we need a post-deployment step to:
>
> 1. Wait for the Gateway to be ready
> 2. Discover the NLB IP address
> 3. Register it with the ALB target group
>
> ```mermaid
> flowchart LR
>     A[Terraform<br/>Layers 1-2<br/><br/>Creates ALB<br/>+ Target Group] --> B[ArgoCD<br/>Layers 3-4<br/><br/>Creates NLB<br/>via Gateway]
>     B --> C[Post-Deploy<br/>Script<br/><br/>Registers<br/>NLB → ALB]
> ```
>
> **Alternative Approach:**
>
> To fully automate this in Terraform, you could modify the Gateway to use `ClusterIP` instead of `LoadBalancer`, then create the NLB Service in Terraform:
>
> ```yaml
> # Gateway with ClusterIP (no auto-created LoadBalancer)
> apiVersion: gateway.networking.k8s.io/v1
> kind: Gateway
> metadata:
>   annotations:
>     networking.istio.io/service-type: ClusterIP  # Prevents NLB creation
> ```
>
> Then Terraform creates a separate Service pointing to the Gateway pods, giving full control over the NLB lifecycle. See the commented alternative in `k8s/istio/gateway.yaml` for details.

## Verification

### Test Web Endpoints (via ALB)

```bash
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)

curl http://${ALB_DNS}/healthz/ready
curl http://${ALB_DNS}/app1
curl http://${ALB_DNS}/app2
curl http://${ALB_DNS}/api/users
```

### Access ArgoCD UI

```bash
# Port forward to ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080
# Username: admin
# Password: terraform output -raw argocd_admin_password
```

### Check ArgoCD Apps

```bash
kubectl get applications -n argocd
```

Expected output:
```
NAME                SYNC STATUS   HEALTH STATUS
gateway-api-crds    Synced        Healthy
istio-base          Synced        Healthy
istio-cni           Synced        Healthy
istiod              Synced        Healthy
ztunnel             Synced        Healthy
namespaces          Synced        Healthy
gateway             Synced        Healthy
httproutes          Synced        Healthy
sample-apps         Synced        Healthy
```

## Cleanup

```bash
# Delete ArgoCD apps first
kubectl delete -f argocd/root-app.yaml

# Wait for resources to be cleaned up
sleep 60

# Destroy infrastructure
cd terraform
terraform destroy
```

## Troubleshooting

### ArgoCD not accessible
```bash
kubectl get pods -n argocd
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Gateway not creating NLB
```bash
# Check Gateway status
kubectl get gateway -n istio-ingress -o yaml

# Check AWS LB Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### NLB registration script fails
```bash
# Check if Gateway is ready
kubectl get gateway -n istio-ingress mtkc-gateway

# Manually get NLB hostname
kubectl get gateway -n istio-ingress mtkc-gateway -o jsonpath='{.status.addresses[0].value}'
```

### Pods not scheduling on correct nodes
```bash
# Check node labels
kubectl get nodes --show-labels | grep role

# Check taints
kubectl describe nodes | grep -A5 Taints
```

---

> **Note:** This is a POC demonstrating how Kubernetes Gateway API can be implemented on AWS EKS with Istio Ambient Mesh. For a more complete production-ready reference architecture including CloudFront, WAF, S3 static assets, and AWS API Gateway, see the [`reference-architecture`](https://github.com/shanaka-versent/EKS-Istio-GatewayAPI-Deom/tree/reference-architecture) branch.

---

## Appendix: Cloud Provider Comparison

This project demonstrates AWS EKS implementation. The following table shows equivalent components for Azure AKS:

| Component | Azure (AKS) | AWS (EKS) |
|-----------|-------------|-----------|
| External L7 LB | Azure App Gateway | AWS ALB |
| Internal L4 LB | Azure Internal LB | AWS Internal NLB |
| LB Controller | cloud-controller-manager | AWS Load Balancer Controller |
| Service Mesh | Istio Gateway | Istio Gateway |
| Gateway API | Same (Kubernetes standard) | Same (Kubernetes standard) |
| GitOps | ArgoCD | ArgoCD |

### Critical Fixes: AKS vs EKS

The [AKS Istio Gateway API implementation](https://github.com/shanaka-versent/AKS-Istio-GatewayAPI-Demo) required two critical fixes. Here's how they apply to EKS:

| Fix | Description | AKS | EKS |
|-----|-------------|-----|-----|
| **Health Probe HTTPRoute** | Route `/healthz/*` to a health-responder service so ALB/App Gateway health probes succeed | Required | Required (implemented) |
| **externalTrafficPolicy: Local** | Prevent SNAT on Internal LB to fix Azure DSR/Floating IP routing | Required | Not required |

**Why Fix 2 is not needed for EKS:**
- Azure App Gateway with Internal LB uses Direct Server Return (DSR) with Floating IP, which requires `externalTrafficPolicy: Local` to prevent SNAT from breaking the return path
- AWS NLB with IP target type uses VPC routing directly to pod IPs, avoiding the SNAT issue entirely

### Fix 1: HTTPRoute for /healthz (Health Probe Routing)

**Problem:** ALB health probes to `/healthz/ready` return 404 errors because the Istio Gateway has no routing rule defined for health check requests.

**Solution:** A dedicated HTTPRoute routes `/healthz/*` paths to a health-responder service that returns 200 OK responses.

```mermaid
flowchart LR
    subgraph ALB["ALB Health Probe"]
        Probe["GET /healthz/ready"]
    end

    subgraph IstioGW["Istio Gateway (Envoy)"]
        Match{"HTTPRoute<br/>Matching?"}
    end

    subgraph Results["Result"]
        NoRoute["NO HTTPRoute<br/>404 Not Found<br/>Target Unhealthy"]
        WithRoute["WITH HTTPRoute<br/>200 OK<br/>Target Healthy"]
    end

    Probe --> Match
    Match -->|"No match"| NoRoute
    Match -->|"Match found"| WithRoute

    style ALB fill:#e3f2fd,stroke:#1976d2
    style IstioGW fill:#e8eaf6,stroke:#466bb0
    style NoRoute fill:#ffebee,stroke:#c62828
    style WithRoute fill:#e8f5e9,stroke:#2e7d32
```

**Implementation Files:**
| File | Purpose |
|------|---------|
| [k8s/istio/httproutes.yaml](k8s/istio/httproutes.yaml) | Defines health-route for `/healthz/*` paths |
| [k8s/apps/health-responder.yaml](k8s/apps/health-responder.yaml) | Deploys nginx pod responding with 200 OK |
| [k8s/istio/httproutes.yaml](k8s/istio/httproutes.yaml) | ReferenceGrant for cross-namespace routing |
