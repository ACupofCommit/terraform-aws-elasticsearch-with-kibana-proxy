// based on https://github.com/trussworks/terraform-aws-ecs-service/blob/f6fe5fa0c2b8e8ecf8e904b4d885dc9302a617f5/examples/load-balancer/main.tf

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  suffix                = var.name_suffix != "" ? var.name_suffix : random_id.suffix.hex
  region                = data.aws_region.current.name
  account_id            = data.aws_caller_identity.current.account_id
  nginx_config_template = base64encode(file("${path.module}/assets/default.template"))
  es_name               = "${var.name_prefix}-${local.suffix}"
  container_port        = 80
  service_port          = 443
  target_container_name = "${var.name_prefix}-kibana-nginx-proxy-${local.suffix}"
  logs_cloudwatch_group = "/ecs/${var.name_prefix}-kibana-nginx-proxy-${local.suffix}"
}

module "acm" {
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "~> v2.0"
  domain_name               = var.kibana_custom_domain
  zone_id                   = var.route53_zone_id
  subject_alternative_names = []
  tags                      = var.tags
}

resource "aws_route53_record" "kibana" {
  count   = var.vpc_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.kibana_custom_domain
  type    = "A"
  alias {
    name                   = aws_lb.main[0].dns_name
    zone_id                = aws_lb.main[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}-user-pool-${local.suffix}"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  tags = var.tags
}

//resource "aws_cognito_user_group" "main" {
//  name         = "${var.name_prefix}-user-group-${local.suffix}"
//  user_pool_id = aws_cognito_user_pool.main.id
//  description  = "${var.name_prefix} user group for kibana access"
//  precedence   = 0
//  role_arn     = "arn:aws:iam::${local.account_id}:role/service-role/CognitoAccessForAmazonES"
//}

# This can not be managed by terraform.
# After elasticsearch deploy, manually destroy it and
# import the resource created by the elasticsearch configuration.
# ex)
# $ terraform destroy -target module.modulename.aws_cognito_user_pool_client.es
# $ terraform import module.modulename.aws_cognito_user_pool_client.es <user_pool_id>/<user_pool_client_id>
# id values can be found in AWS Console cognito page.
resource "aws_cognito_user_pool_client" "es" {
  user_pool_id = aws_cognito_user_pool.main.id
  lifecycle {
    ignore_changes = [
      name,
      allowed_oauth_flows_user_pool_client, supported_identity_providers,
      allowed_oauth_flows, allowed_oauth_scopes,
      explicit_auth_flows,
    ]
  }

  allowed_oauth_flows_user_pool_client = true
  name                                 = "this-resource-will-be-destroyed-${local.suffix}"
  callback_urls = [
    "https://${var.kibana_custom_domain}/_plugin/kibana/app/kibana",
    "https://${aws_elasticsearch_domain.es.endpoint}/_plugin/kibana/app/kibana",
  ]
  logout_urls = [
    "https://${var.kibana_custom_domain}/_plugin/kibana/app/kibana",
    "https://${aws_elasticsearch_domain.es.endpoint}/_plugin/kibana/app/kibana",
  ]
  allowed_oauth_flows          = ["code"]              // code, implicit, client_credentials).
  allowed_oauth_scopes         = ["openid", "profile"] // phone, email, openid, profile, and aws.cognito.signin.user.admin).
  supported_identity_providers = []
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "es-user-pool-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "identity pool for cognito"
  allow_unauthenticated_identities = true

  // It should not be modify after ES creation
  lifecycle {
    ignore_changes = [cognito_identity_providers]
  }
}

module "lambda_security_group" {
  count       = var.vpc_id != "" ? 1 : 0
  source      = "terraform-aws-modules/security-group/aws"
  name        = "${var.name_prefix}-lambda-${local.suffix}"
  description = "${var.name_prefix} lambda security group"
  vpc_id      = var.vpc_id

  egress_with_source_security_group_id = [{
    rule        = "https-443-tcp"
    source_security_group_id = module.es_security_group[0].this_security_group_id
  }]
}

module "es_security_group" {
  count       = var.vpc_id != "" ? 1 : 0
  source      = "terraform-aws-modules/security-group/aws"
  name        = "${var.name_prefix}-es-${local.suffix}"
  description = "${var.name_prefix} elasticsearch security group"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    for s in var.public_subnets_cidr_blocks : {
      rule        = "https-443-tcp"
      cidr_blocks = s
    }
  ]
  ingress_with_source_security_group_id = [{
    rule        = "https-443-tcp"
    source_security_group_id = module.lambda_security_group[0].this_security_group_id
  }]
}

resource "aws_elasticsearch_domain" "es" {
  domain_name           = local.es_name
  elasticsearch_version = "7.9"

  cluster_config {
    instance_type = var.es_instance_type
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.es_ebs_volume_size
  }

  dynamic "vpc_options" {
    for_each = var.vpc_id != "" ? [true] : []
    content {
      subnet_ids         = var.es_node_number != null ? slice(var.private_subnets, 0, var.es_node_number) : var.private_subnets
      security_group_ids = [module.es_security_group[0].this_security_group_id]
    }
  }

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https                   = true
    tls_security_policy             = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled         = var.vpc_id != "" ? false : true
    custom_endpoint                 = var.kibana_custom_domain
    custom_endpoint_certificate_arn = module.acm.this_acm_certificate_arn
  }

  advanced_security_options {
    enabled = true
    master_user_options {
      master_user_arn = var.es_master_user_arn != "" ? var.es_master_user_arn : aws_iam_role.authenticated.arn
    }
  }

  cognito_options {
    enabled          = true
    user_pool_id     = aws_cognito_user_pool.main.id
    identity_pool_id = aws_cognito_identity_pool.main.id
    role_arn         = "arn:aws:iam::${local.account_id}:role/service-role/CognitoAccessForAmazonES"
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  // "AWS": "arn:aws:sts::${local.account_id}:assumed-role/${aws_iam_role.authenticated.name}/CognitoIdentityCredentials"
  access_policies = <<CONFIG
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "es:*",
            "Principal": {
              "AWS": "*"
            },
            "Effect": "Allow",
            "Resource": "arn:aws:es:${local.region}:${local.account_id}:domain/${local.es_name}/*"
        }
    ]
}
CONFIG

  snapshot_options {
    automated_snapshot_start_hour = 23
  }

  tags = {
    Domain = "TestDomain"
  }
}

resource "aws_iam_role" "authenticated" {
  name = "cognito_authenticated"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.main.id}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "authenticated" {
  name = "authenticated_policy"
  role = aws_iam_role.authenticated.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*",
        "cognito-identity:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "unauthenticated" {
  name = "cognito_unauthenticated"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.main.id}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "unauthenticated"
        }
      }
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "unauthenticated" {
  name = "authenticated_policy"
  role = aws_iam_role.unauthenticated.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated"   = aws_iam_role.authenticated.arn
    "unauthenticated" = aws_iam_role.unauthenticated.arn
  }
}

#
# KMS
#

data "aws_iam_policy_document" "cloudwatch_logs_allow_kms" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }
    actions = [
      "kms:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Allow logs KMS access"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "main" {
  description         = "${var.name_prefix} Key for ECS log encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.cloudwatch_logs_allow_kms.json
}

#
# ECS Cluster
#

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-${local.suffix}"
}

#
# ALB
#
resource "aws_lb" "main" {
  count              = var.vpc_id != "" ? 1 : 0
  name               = "${var.name_prefix}-${local.suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg[0].id]
  subnets            = var.public_subnets
}

resource "aws_lb_listener" "http" {
  count             = length(aws_lb.main)
  load_balancer_arn = aws_lb.main[0].id
  port              = local.service_port
  protocol          = "HTTPS"
  certificate_arn   = module.acm.this_acm_certificate_arn

  default_action {
    target_group_arn = aws_lb_target_group.http.id
    type             = "forward"
  }
}

resource "aws_lb_target_group" "http" {
  name     = "${var.name_prefix}-${local.container_port}-v5"
  port     = local.container_port
  protocol = "HTTP"
  lifecycle {
    create_before_destroy = true
  }

  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 90

  health_check {
    port                = local.container_port
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    path                = "/health"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }

  depends_on = [aws_lb.main]
}

resource "aws_security_group" "lb_sg" {
  count  = var.vpc_id != "" ? 1 : 0
  name   = "${var.name_prefix}-service-lb-${local.suffix}"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "app_lb_allow_outbound" {
  count                    = var.vpc_id != "" ? 1 : 0
  security_group_id        = aws_security_group.lb_sg[0].id
  type                     = "egress"
  from_port                = local.container_port
  to_port                  = local.container_port
  protocol                 = "-1"
  source_security_group_id = module.es_security_group[0].this_security_group_id
}

resource "aws_security_group_rule" "app_lb_allow_outbound_2" {
  count             = var.vpc_id != "" ? 1 : 0
  security_group_id = aws_security_group.lb_sg[0].id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app_lb_allow_outbound_3" {
  count                    = var.vpc_id != "" ? 1 : 0
  security_group_id        = aws_security_group.lb_sg[0].id
  type                     = "egress"
  from_port                = local.container_port
  to_port                  = local.container_port
  protocol                 = "tcp"
  source_security_group_id = module.ecs-service-kibana-proxy[0].ecs_security_group_id
}

resource "aws_security_group_rule" "app_lb_allow_all_http" {
  count             = var.vpc_id != "" ? 1 : 0
  security_group_id = aws_security_group.lb_sg[0].id
  type              = "ingress"
  from_port         = local.service_port
  to_port           = local.service_port
  protocol          = "tcp"
  cidr_blocks       = var.service_ingress_cidr_rules
}

#
# ECS Service
#
module "ecs-service-kibana-proxy" {
  source = "trussworks/ecs-service/aws"
  count  = var.vpc_id != "" ? 1 : 0

  name        = var.name_prefix
  environment = local.suffix

  associate_alb = var.associate_alb
  associate_nlb = var.associate_nlb

  alb_security_group     = aws_security_group.lb_sg[0].id
  nlb_subnet_cidr_blocks = null

  lb_target_groups = [
    {
      lb_target_group_arn         = aws_lb_target_group.http.arn
      container_port              = local.container_port
      container_health_check_port = local.container_port
    },
  ]

  ecs_cluster      = aws_ecs_cluster.main
  ecs_subnet_ids   = var.public_subnets // TODO: when NAT is used, check that private subnets is availabled
  ecs_vpc_id       = var.vpc_id
  ecs_use_fargate  = true
  assign_public_ip = true

  kms_key_id = aws_kms_key.main.arn

  cloudwatch_alarm_cpu_enable = false
  cloudwatch_alarm_mem_enable = false
  target_container_name       = local.target_container_name
  logs_cloudwatch_group       = local.logs_cloudwatch_group

  container_definitions = jsonencode([
    {
      name      = local.target_container_name
      image     = "nginx:1.19.9-alpine"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.logs_cloudwatch_group
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "helloworld"
        }
      }
      environment = [
        { name : "KIBANA_HOST", value : var.kibana_custom_domain },
        { name : "ES_HOST", value : aws_elasticsearch_domain.es.endpoint },
        { name : "COGNITO_HOST", value : aws_cognito_user_pool_domain.main.cloudfront_distribution_arn },
        { name : "COGNITO_CLIENT_ID", value : aws_cognito_user_pool_client.es.id },
        { name : "AWS_REGION", value : local.region },
        { name : "USER_POOL_DOMAIN", value : aws_cognito_user_pool_domain.main.domain },
      ]
      mountPoints = []
      volumesFrom = []
      entryPoint = [
        "/bin/sh", "-c",
        "echo '${local.nginx_config_template}' | base64 -d > /tmp/default.template && envsubst < /tmp/default.template > /etc/nginx/conf.d/default.conf && cat /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
      ]
    }
  ])
}

