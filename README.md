# Amazon EKS Terraform 예제

이 저장소는 Terraform을 사용하여 Amazon EKS 환경을 구축하기 위한 예제 구성을 제공합니다.

## 구성 목록

### eks-auto-mode

EKS Auto Mode를 사용하여 클러스터를 구성합니다.

EKS Auto Mode는 노드 프로비저닝, 오토스케일링, 로드 밸런싱 등의 기능을 AWS에서 관리하므로 운영 복잡도를 줄일 수 있습니다.

#### 포함 구성요소

* Argo CD
* Prometheus Stack

  * Prometheus
  * Alertmanager
  * Grafana
* Locust
* ExternalDNS
* Metrics Server

---

### eks-standard

기존 방식의 Amazon EKS 클러스터를 구성합니다.

노드 프로비저닝 및 오토스케일링은 Karpenter를 사용하며, AWS Load Balancer Controller를 별도로 설치합니다.

#### 포함 구성요소

* Karpenter
* AWS Load Balancer Controller
* Argo CD
* Prometheus Stack

  * Prometheus
  * Alertmanager
  * Grafana
* Locust
* ExternalDNS
* Metrics Server

---

## 구성 비교

| 구성요소                         | eks-auto-mode | eks-standard |
| ---------------------------- | ------------- | ------------ |
| Argo CD                      | ✅             | ✅            |
| Prometheus Stack             | ✅             | ✅            |
| Locust                       | ✅             | ✅            |
| ExternalDNS                  | ✅             | ✅            |
| Metrics Server               | ✅             | ✅            |
| Karpenter                    | Built-in         | ✅            |
| AWS Load Balancer Controller | Built-in         | ✅            |

---

## 사전 준비 사항

* Terraform 1.6 이상
* AWS CLI
* kubectl
* Helm
* EKS 및 관련 리소스를 생성할 수 있는 AWS 권한

---

## 배포 방법

### EKS Auto Mode

```bash
cd eks-auto-mode

terraform init
terraform plan
terraform apply
```

### EKS Standard

```bash
cd eks-standard

terraform init
terraform plan
terraform apply
```

---

## 참고 사항

* `eks-auto-mode`는 EKS Auto Mode의 기본 기능을 최대한 활용하는 구성입니다.
* `eks-standard`는 Karpenter 및 AWS Load Balancer Controller를 별도로 구성하는 전통적인 EKS 운영 방식입니다.
* Argo CD를 통해 추가 애플리케이션을 GitOps 방식으로 배포하고 관리할 수 있습니다.
* Prometheus Stack을 통해 클러스터 및 애플리케이션 모니터링 환경을 제공합니다.