output "cluster_name" {
  value = kind_cluster.this.name
}

output "context_name" {
  value = kind_cluster.this.context_name
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}
