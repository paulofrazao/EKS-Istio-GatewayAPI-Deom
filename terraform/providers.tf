# MTKC POC EKS - Terraform Providers
# @author Shanaka Jayasundera - shanakaj@gmail.com

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# cluster-a: us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = var.cluster_a_region

  default_tags {
    tags = var.tags
  }
}

# cluster-b: us-west-1
provider "aws" {
  alias  = "us_west_1"
  region = var.cluster_b_region

  default_tags {
    tags = var.tags
  }
}

# Kubernetes provider for cluster-a
provider "kubernetes" {
  alias                  = "cluster_a"
  host                   = module.eks_a.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_a.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_a.cluster_name, "--region", var.cluster_a_region]
  }
}

# Kubernetes provider for cluster-b
provider "kubernetes" {
  alias                  = "cluster_b"
  host                   = module.eks_b.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_b.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_b.cluster_name, "--region", var.cluster_b_region]
  }
}

# Helm provider for cluster-a
provider "helm" {
  alias = "cluster_a"
  kubernetes {
    host                   = module.eks_a.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_a.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_a.cluster_name, "--region", var.cluster_a_region]
    }
  }
}

# Helm provider for cluster-b
provider "helm" {
  alias = "cluster_b"
  kubernetes {
    host                   = module.eks_b.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_b.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_b.cluster_name, "--region", var.cluster_b_region]
    }
  }
}
