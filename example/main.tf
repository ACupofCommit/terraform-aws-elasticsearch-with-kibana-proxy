data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

provider "aws" {
  region = "ap-northeast-1"
}

locals {
  name_prefix = "ewkp-example" # ewkp means Elasticsearch with Kibana Proxy
  region      = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id
}

module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  version         = "~> 2.64.0"
  name            = "${local.name_prefix}-vpc"
  cidr            = "10.0.0.0/16"
  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.104.0/24", "10.0.105.0/24"]
}

data "aws_route53_zone" "selected" {
  name         = "example.com."
  private_zone = false
}

module "es_and_kibana" {
  source                     = "../"
  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnets
  public_subnet_cidr_blocks  = module.vpc.public_subnets_cidr_blocks
  private_subnet_ids         = module.vpc.private_subnets
  private_subnet_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  route53_zone_id            = data.aws_route53_zone.selected.zone_id
  kibana_custom_domain       = "kibana.example.com"
  es_availability_zone_count = 2
  es_node_type               = "t3.medium.elasticsearch"
  es_node_count              = 2
  es_master_node_count       = 3
  es_master_node_type        = "t3.medium.elasticsearch"
  es_node_to_node_encryption = true
  es_encrypt_at_rest         = true
}

output "output" {
  value = module.es_and_kibana.output
}
