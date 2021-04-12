output "output" {
  description = "Resource information for accessing elasticsearch"
  value       = <<EOT
# Belows are used by lambda
export ES_HOST=${aws_elasticsearch_domain.es.endpoint}
export ES_NAME=${aws_elasticsearch_domain.es.domain_name}
export SECURITY_GROUP_ID=${length(module.lambda_security_group) > 0 ? module.lambda_security_group[0].this_security_group_id : ""}
EOT
}

output "es_name" {
  value       = aws_elasticsearch_domain.es.domain_name
  description = "elasticsearch_domain name"
}
