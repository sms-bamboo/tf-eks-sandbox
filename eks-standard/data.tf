# AWS 지역 정보 불러오기
data "aws_region" "current" {}

# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}

# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}

# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# secret manager 사용 시
# data "aws_secretsmanager_secret_version" "this" {
#  secret_id = local.project
#}

# Route53 호스트존
data "aws_route53_zone" "this" {
  name = "${local.service_domain_name}."
}

# 내 IP 가져오기
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}