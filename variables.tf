variable "name_prefix" {
  type = string
  default = "terraform-es"
}

variable "name_suffix" {
  type = string
  default = ""
}

variable "kibana_custom_domain" {
  type = string
  description = "Domain for kibana access"
}

variable "route53_zone_id" {
  type = string
  description = "Route53 zone id for kibana_proxy_host"
}

variable "vpc_id" {
  type = string
  default = ""
}

variable "vpc_cidr" {
  type = string
  default = ""
}

variable "public_subnets" {
  type = list(string)
  default = []
}
variable "public_subnets_cidr_blocks" {
  type = list(string)
  default = []
}

variable "private_subnets" {
  type = list(string)
  default = []
}
variable "private_subnets_cidr_blocks" {
  type = list(string)
  default = []
}

variable "es_instance_type" {
  type = string
  default = "t3.medium.elasticsearch"
}

variable "es_ebs_volume_size" {
  type = number
  default = 10
}

variable "es_node_number" {
  type = number
  description = "Use it when you want to create es with nodes smaller than the number of private_subnets provided. It only makes sense when using vpc."
  default = null
}

variable "es_master_user_arn" {
  type = string
  default = null
}

variable "service_ingress_cidr_rules" {
  type = list(string)
  default = ["0.0.0.0/0"]
}

variable "create_kibana_proxy" {
  type = bool
  default = false
}

variable "associate_alb" {
  type = bool
  default = true
}

variable "associate_nlb" {
  type = bool
  default = false
}

variable "tags" {
  type = map(string)
  default = {}
}
