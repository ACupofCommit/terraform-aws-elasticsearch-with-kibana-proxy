output "output" {

  value = <<EOT
# Belows are used by lambda
export ES_HOST=${aws_elasticsearch_domain.es.endpoint}
export ES_NAME=${aws_elasticsearch_domain.es.domain_name}
export SECURITY_GROUP_ID=${length(module.lambda_security_group) > 0 ? module.lambda_security_group[0].this_security_group_id : ""}
export PRIVATE_SUBNET_ID1=${var.private_subnets[0]}
export PRIVATE_SUBNET_ID2=${var.private_subnets[1]}
EOT
}

output "es_name" {
  value = aws_elasticsearch_domain.es.domain_name
}
