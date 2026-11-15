include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules/kind-cluster"
}

# root.hcl 의 inputs(env.hcl 값)에 이 unit 전용 값을 더한다
inputs = {
  kubeconfig_path = "${get_env("HOME")}/.kube/k8s-lab/${local.env.cluster_name}.yaml"
}
