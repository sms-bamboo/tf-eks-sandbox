# Argo CD를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

# 테스트 용도 이외에는 외부 저장소(secret manager) 사용 권장
# Argo CD 어드민 비밀번호의 bcrypt hash 생성
# resource "htpasswd_password" "argocd" {
#   password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["argocd"]["adminPassword"]
# }

resource "random_password" "argocd_admin_password" {
  length           = 24
  special          = true
  override_special = "_%@"
}

resource "htpasswd_password" "argocd" {
  password = random_password.argocd_admin_password.result
}

# Argo CD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/argocd.yaml", {
      domain                            = "argocd.${local.service_domain_name}"
      server_admin_password             = htpasswd_password.argocd.bcrypt
    })
  ]
}

# Prometheus를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana_admin_password" {
  length           = 24
  special          = true
  override_special = "_%@"
}

# Kube-prometheus-stack
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace_v1.prometheus.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/prometheus.yaml", {
      cluster_name                      = module.eks.cluster_name
      prometheus_hostname        = "prometheus.${local.service_domain_name}"
      alertmanager_hostname             = "alertmanager.${local.service_domain_name}"
      grafana_hostname                  = "grafana.${local.service_domain_name}"
      grafana_admin_password            = random_password.grafana_admin_password.result
      # 테스트 용도 이외에는 외부 저장소(secret manager) 사용 권장
      # grafana_admin_password            = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["grafana"]["adminPassword"]
      thanos_bucket                     = aws_s3_bucket.thanos.id
      thanos_hostname                   = "thanos.${local.service_domain_name}"
    })
  ]
}

# Thanos 사이드카에서 Prometheus 지표를 보낼 버킷
resource "aws_s3_bucket" "thanos" {
  bucket = "${local.project}-thanos-storage"

  force_destroy = true
}

resource "aws_iam_policy" "thanos" {
  name = "thanos-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.thanos.arn,
          "${aws_s3_bucket.thanos.arn}/*"
        ]
      }
    ]
  })
}

module "thanos_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "thanos"

  additional_policy_arns = {
    additional = aws_iam_policy.thanos.arn
  }

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.prometheus.metadata[0].name
      service_account = "kube-prometheus-prometheus"
    }
  }
}

module "thanos_compactor_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "thanos"

  additional_policy_arns = {
    additional = aws_iam_policy.thanos.arn
  }

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.prometheus.metadata[0].name
      service_account = "thanos-thanos"
    }
  }
}

# Thanos
resource "helm_release" "thanos" {
  name       = "thanos"
  repository = "oci://ghcr.io/thanos-community/helm-charts"
  chart      = "thanos"
  version    = var.thanos_chart_version
  namespace  = kubernetes_namespace_v1.prometheus.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/thanos.yaml", {
      thanos_bucket                = aws_s3_bucket.thanos.id
      compactor_hostname           = "thanos-compactor.${local.service_domain_name}"
      storegateway_hostname        = "thanos-storegateway.${local.service_domain_name}"
      query_hostname               = "thanos-query.${local.service_domain_name}"
      queryfrontend_hostname               = "thanos-queryfrontend.${local.service_domain_name}"
    })
  ]

  depends_on = [
    helm_release.prometheus
  ]
}

# Locust를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "locust" {
  metadata {
    name = "locust"
  }
}

# Locust
resource "helm_release" "locust" {
  name       = "locust"
  repository = "https://charts.deliveryhero.io"
  chart      = "locust"
  version    = var.locust_chart_version
  namespace  = kubernetes_namespace_v1.locust.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/locust.yaml", {
      hostname = "locust.${local.service_domain_name}"
    })
  ]
}

resource "kubernetes_config_map_v1" "locustfile" {
  metadata {
    name      = "locustfile"
    namespace = kubernetes_namespace_v1.locust.metadata[0].name
  }

  data = {
    "main.py" = <<-EOT
      from locust import HttpUser, task, between

      class MyUser(HttpUser):
          wait_time = between(1, 3)

          @task
          def index(self):
              self.client.get("/")

          @task(2)
          def about(self):
              self.client.get("/about")
    EOT
  }
}

# ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/external-dns.yaml", {
      txtOwnerId = module.eks.cluster_name
    })
  ]
}

module "external_dns_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.this.arn]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }
}