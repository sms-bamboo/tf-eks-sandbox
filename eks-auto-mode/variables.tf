variable "vpc_cidr" {
  description = "VPC 대역대"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
}

variable "eks_cluster_endpoint_public_access" {
  description = "EKS 엔드포인트에 대한 퍼블릭 접근 허가"
  default     = false
  type        = bool
}

variable "metrics_server_chart_version" {
  description = "Kubernetes Metrics Server Helm 차트 버전"
  type        = string
}

variable "external_dns_chart_version" {
  description = "Kubernetes ExternalDNS Helm 차트 버전"
  type        = string
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm 차트 버전 "
  type        = string
}

variable "kube_prometheus_stack_chart_version" {
  description = "Kube-prometheus-stack Helm 차트 버전 "
  type        = string
}

variable "thanos_chart_version" {
  description = "Thanos Helm 차트 버전 "
  type        = string
}

variable "kubecost_chart_version" {
  description = "Kubecost Helm 차트 버전 "
  type        = string
}

variable "locust_chart_version" {
  description = "Locust Helm 차트 버전 "
  type        = string
}

variable "k8tz_chart_version" {
  description = "k8tz Helm 차트 버전 "
  type        = string
}

variable "kubernetes_event_exporter_chart_version" {
  description = "Kubernetes Event Exporter Helm 차트 버전 "
  type        = string
}