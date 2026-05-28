module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.0"

  name = local.project
  cidr = var.vpc_cidr

  azs              = data.aws_availability_zones.azs.names
  public_subnets   = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets  = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 10)]
  
  default_security_group_egress = [
    {
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  # public LB 생성할 서브넷에 지정하는 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  # private LB 생성할 서브넷에 지정하는 태그
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}