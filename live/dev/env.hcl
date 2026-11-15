# dev 환경 값. stg 를 만들 때는 이 파일만 복사해서 값을 바꾼다 (2주차).
locals {
  env          = "dev"
  cluster_name = "k8s-lab-dev"
  node_image   = "kindest/node:v1.34.11" # 운영 중인 EKS 1.34 와 맞춤 (kind v0.33.0 기준 이미지)
  worker_count = 1
}
