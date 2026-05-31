terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.3.0"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = ">= 2.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.5.0"
    }
  }
}

# AWS 제공자 설정
provider "aws" {
  default_tags {
    tags = local.tags
  }
}

# Kubernetes 제공자 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Helm 제공자 설정
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
  debug = true
}

# Kubectl 제공자 설정
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  lazy_load              = true
}