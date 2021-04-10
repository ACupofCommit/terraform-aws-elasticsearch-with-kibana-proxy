data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  vpc_azs     = ["ap-northeast-1a", "ap-northeast-1c"]
  name_prefix = "example-es"
  region      = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.64.0"

  name = "example-es-vpc"
  cidr = "10.0.0.0/16"
  azs  = local.vpc_azs

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.104.0/24", "10.0.105.0/24"]
}

data "aws_route53_zone" "selected" {
  name         = "aluc.io."
  private_zone = false
}

resource "aws_iam_role" "lambda_excution_role" {
  name               = "${local.name_prefix}-lambda-excution-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "labmda_excution_role_policy" {
  name = "${local.name_prefix}-lambda-excution-role-policy"
  role = aws_iam_role.lambda_excution_role.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "logs:CreateLogStream",
                "logs:CreateLogGroup"
            ],
            "Resource": [
                "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/*:*"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/*:*:*"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "es:*"
            ],
            "Resource": [
                "arn:aws:es:ap-northeast-1:539425821792:domain/${module.es_and_kibana.es_name}/*"
            ],
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.lambda_excution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

module "es_and_kibana" {
  source                      = "../"
  name_prefix                 = local.name_prefix
  vpc_id                      = module.vpc.vpc_id
  es_node_number              = 1
  public_subnets              = module.vpc.public_subnets
  public_subnets_cidr_blocks  = module.vpc.public_subnets_cidr_blocks
  private_subnets             = module.vpc.private_subnets
  private_subnets_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  kibana_custom_domain        = "kibana4.aluc.io"
  es_master_user_arn          = aws_iam_role.lambda_excution_role.arn
  route53_zone_id             = data.aws_route53_zone.selected.zone_id
}


output "output" {
  value = module.es_and_kibana.output
}

output "lambda_execution_role_arn" {
  value = aws_iam_role.lambda_excution_role.arn
}
