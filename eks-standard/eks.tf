module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name    = local.project
  kubernetes_version = var.eks_cluster_version

  endpoint_public_access = true
  endpoint_public_access_cidrs = ["${chomp(data.http.my_ip.response_body)}/32"]

  # EKS Add-on
  addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        # Karpenter가 실행되려면 CoreDNS가 필수 구성요소기 때문에 Fargate에 배포
        computeType = "Fargate"
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256M"
          }
          requests = {
            cpu    = "0.25"
            memory = "256M"
          }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id = module.vpc.vpc_id
  # 노드그룹 사용 시 노드가 생성되는 서브넷
  subnet_ids = module.vpc.private_subnets
  # 컨트롤 플레인으로 연결된 ENI를 생성할 서브넷
  control_plane_subnet_ids = module.vpc.intra_subnets

  enable_cluster_creator_admin_permissions = true
  create_node_security_group = false

  fargate_profiles = {
    # Karpenter를 Fargate에 실행
    karpenter = {
      selectors = [
        {
          namespace = "karpenter"
        }
      ]
    }
    # CoreDNS를 Fargate에 실행
    coredns = {
      selectors = [
        {
          namespace = "kube-system"

          labels = {
            k8s-app = "kube-dns"
          }
        }
      ]
    }
  }

  # 로깅 비활성화
  enabled_log_types = []
}

module "aws_ebs_csi_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "aws-ebs-csi"

  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = {
    Environment = "dev"
  }
}

# Kapenter IRSA 권한
data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}


# Karpenter 구성에 필요한 AWS 리소스 생성
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name                  = module.eks.cluster_name
  namespace                     = kubernetes_namespace_v1.karpenter.metadata[0].name
  node_iam_role_name            = "${module.eks.cluster_name}-node-role"
  node_iam_role_use_name_prefix = false
  create_pod_identity_association = false
  enable_inline_policy          = true

  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json,
  ]

  # Karpenter가 생성할 노드에 부여할 역할에 기본 정책 이외에 추가할 IAM 정책
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

# Karpenter를 배포할 네임 스페이스
resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

# Karpenter
resource "helm_release" "karpenter-crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace_v1.karpenter.metadata[0].name
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace_v1.karpenter.metadata[0].name

  skip_crds = true

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
      featureGates:
        spotToSpotConsolidation: true
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    serviceMonitor:
      enabled: true
    controller:
      env:
        - name: AWS_REGION
          value: ${data.aws_region.current.region}       
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
    EOT
  ]
}

# EBS CSI 드라이버를 사용하는 스토리지 클래스
resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# 기본값으로 생성된 스토리지 클래스 해제
resource "kubernetes_annotations" "default_storageclass" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"

  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  depends_on = [
    kubernetes_storage_class_v1.ebs_sc
  ]
}

# Metrics Server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"
}

# Karpenter 기본 노드 클래스
resource "kubectl_manifest" "karpenter_default_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2023
      role: ${module.karpenter.node_iam_role_name}
      amiSelectorTerms:
      - alias: al2023@latest
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
      - id: ${module.eks.cluster_primary_security_group_id}
      blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 20Gi
          volumeType: gp3
          encrypted: true
      tags:
        ${jsonencode(local.tags)}
    YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# Karpenter 기본 노드 풀
resource "kubectl_manifest" "karpenter_default_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      weight: 50
      template:
        spec:
          expireAfter: 720h
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: karpenter.k8s.aws/instance-category
            operator: In
            values: ["t","m","c","r"]
          - key: karpenter.k8s.aws/instance-generation
            operator: Gt
            values: ["2"]
          - key: karpenter.k8s.aws/instance-memory
            operator: Gt
            values: ["2048"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
  YAML

  depends_on = [
    kubectl_manifest.karpenter_default_node_class
  ]
}

# AWS Load Balancer Controller에 부여할 IAM 역할 및 Pod Identity Association
module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.7.0"

  name = "aws-load-balancer-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    (module.eks.cluster_name) = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    vpcId: ${module.vpc.vpc_id}
    region: ${data.aws_region.current.region}
    clusterName: ${module.eks.cluster_name}
    defaultTargetType: ip
    serviceAccount:
      create: true
    ingressClassParams:
      spec:
        certificateArn:
          - ${aws_acm_certificate.service_domain.arn}
        scheme: internet-facing
        group:
          name: kube-apps
        sslRedirectPort: "443"
    EOT
  ]

  depends_on = [
    module.eks
  ]

}

#resource "kubectl_manifest" "alb_ingress_class_params" {
#  yaml_body = <<-YAML
#  apiVersion: elbv2.k8s.aws/v1beta1
#  kind: IngressClassParams
#  metadata:
#    name: alb
#  spec:
#    certificateARNs: 
#    - ${aws_acm_certificate.service_domain.arn}
#    scheme: internet-facing
#    group:
#      name: kube-apps
#  YAML
#
#  depends_on = [
#    helm_release.aws_load_balancer_controller
#  ]
#}