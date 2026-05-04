# 로컬 환경변수
locals {
  project             = "bamboo-dev"
  service_domain_name = "bamboo.sarl"
  
  tags                = {}
  
  whitelist_ip_range = [
    "0.0.0.0/0"           # 임시
  ]
}