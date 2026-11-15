# root.hcl: 모든 unit(terragrunt.hcl)이 include 하는 공통 설정
# 1주차 포인트: backend와 provider 설정을 여기 한 곳에만 둔다.

# Terraform 을 사용 (OpenTofu 가 설치돼 있어도 terraform 을 실행하도록 고정)
terraform_binary = "terraform"

locals {
  # 자식 unit 위치에서 위로 올라가며 가장 가까운 env.hcl 을 읽는다 (dev/stg 값 분리)
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# state 저장 위치. 로컬 실습이므로 local backend 를 쓰되,
# unit 경로별로 state 파일이 자동으로 분리되게 한다.
#   live/dev/cluster  →  .state/live/dev/cluster/terraform.tfstate
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_parent_terragrunt_dir()}/.state/${path_relative_to_include()}/terraform.tfstate"
  }
}

# provider 블록을 각 unit 에 자동 생성 (모듈에는 required_providers 만 둔다)
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "kind" {}
  EOT
}

# env.hcl 의 locals 를 모든 unit 의 공통 입력값으로 전달
inputs = local.env_vars.locals
