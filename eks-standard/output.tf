# 랜덤 생성 패스워드 확인
# terraform output -raw <output_name>

output "grafana_admin_password" {
  value     = random_password.grafana_admin_password.result
  sensitive = true
}

output "argocd_admin_password" {
  value     = random_password.argocd_admin_password.result
  sensitive = true
}