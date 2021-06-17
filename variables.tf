variable "name_prefix" {
  type        = string
  default     = "terraform-es"
  description = "For most of resource names"
}

variable "name_suffix" {
  type        = string
  description = "If omitted, random string is used."
  default     = ""
}

variable "kibana_custom_domain" {
  type        = string
  description = "Domain for kibana access"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 zone id for kibana_proxy_host"
}

variable "vpc_id" {
  type        = string
  description = "If you provide vpc_id, elasticsearch will be deployed in that vpc. Or it is distributed outside the vpc."
}

variable "use_vpc" {
  type    = bool
  default = true
}

variable "public_subnet_ids" {
  type    = list(string)
  default = []
}
variable "public_subnet_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}
variable "private_subnet_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "es_node_type" {
  type    = string
  default = "t3.medium.elasticsearch"
}

variable "es_ebs_volume_size" {
  type    = number
  default = 10
}

variable "es_node_count" {
  type        = number
  description = "For two or three Availability Zones, we recommend instances in multiples of az count for equal distribution across the Availability Zones."
  default     = 1
}

variable "es_master_user_password" {
  type    = string
  default = "Change-me!-123"
}

variable "es_master_node_count" {
  type        = number
  description = "Dedicated master node count. 0 means that dedecated master nodes are not used."
  default     = 0
}

variable "es_master_node_type" {
  type    = string
  default = "m3.medium.elasticsearch"
}

variable "es_node_to_node_encryption" {
  type    = bool
  default = false
}

variable "es_encrypt_at_rest" {
  type    = bool
  default = false
}

variable "es_availability_zone_count" {
  type        = number
  description = "Number of Availability Zones for the domain to use with zone_awareness_enabled. 1 means the zone_awareness_enabled is false"
  default     = 1
}

variable "service_ingress_cidr_rules" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "create_consumer_security_group" {
  type    = bool
  default = false
}

variable "consumer_security_group_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
