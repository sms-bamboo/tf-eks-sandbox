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
    })
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