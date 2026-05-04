# Ingress NGINX를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# Ingress NGINX
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version
  namespace  = kubernetes_namespace_v1.ingress_nginx.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/ingress-nginx.yaml", {
      lb_acm_certificate_arn = aws_acm_certificate_validation.service_domain.certificate_arn
      whitelist_source_range = join(",", local.whitelist_ip_range)
    })
  ]
}

# Argo CD를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Argo CD 어드민 비밀번호의 bcrypt hash 생성
resource "htpasswd_password" "argocd" {
  password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["argocd"]["adminPassword"]
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

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# Prometheus를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "monitoring"
  }
}

# Grafana assume 정책 설정
resource "aws_iam_policy" "grafana_account_access" {
  name = "grafana-account-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect = "Allow"
        Resource = [
          "*"
        ]
      },
    ]
  })
}

module "grafana_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${module.eks.cluster_name}-cluster-grafana-role"

  role_policy_arns = {
    grafana_account_access = aws_iam_policy.grafana_account_access.arn
  }

  oidc_providers = {
    grafana = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "monitoring:prometheus-grafana"
      ]
    }
  }
}

# Alertmanager 접근 비밀번호
resource "htpasswd_password" "alertmanager" {
  password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["alertmanager"]["password"]
}


resource "kubernetes_secret_v1" "alertmanager" {
  metadata {
    name      = "alertmanager-password"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  data = {
    auth = "admin:${htpasswd_password.alertmanager.bcrypt}"
  }

  type = "Opaque"
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
      alertmanager_hostname             = "alertmanager.${local.service_domain_name}"
      grafana_hostname                  = "grafana.${local.service_domain_name}"
      grafana_role_arn                  = module.grafana_irsa.iam_role_arn
      alertmanager_password_secret_name = kubernetes_secret_v1.alertmanager.metadata[0].name
      grafana_admin_password            = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["grafana"]["adminPassword"]
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
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

  depends_on = [
    helm_release.ingress_nginx
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