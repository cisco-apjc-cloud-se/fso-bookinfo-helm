output "svc" {
  value = data.kubectl-query_services.svc
}

output "pods" {
  value = data.kubectl-query_services.pods
}
