// based on https://github.com/trussworks/terraform-aws-ecs-service/blob/f6fe5fa0c2b8e8ecf8e904b4d885dc9302a617f5/examples/load-balancer/main.tf

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  region                = data.aws_region.current.name
  account_id            = data.aws_caller_identity.current.account_id
  nginx_config_template = base64encode(file("${path.module}/assets/default.template"))
  es_name               = "${var.name_prefix}-${var.name_suffix}"
  container_port        = 80
  target_container_name = "${var.name_prefix}-kibana-nginx-proxy-${var.name_suffix}"
  ecs_log_group_name    = "/ecs/${var.name_prefix}-kibana-nginx-proxy-${var.name_suffix}"
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
  count   = var.use_vpc ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.kibana_custom_domain
  type    = "A"
  alias {
    name                   = aws_lb.main[0].dns_name
    zone_id                = aws_lb.main[0].zone_id
    evaluate_target_health = true
  }
}

module "lambda_security_group" {
  count       = var.create_consumer_security_group && var.use_vpc ? 1 : 0
  source      = "terraform-aws-modules/security-group/aws"
  version     = "~> v4.2.0"
  name        = "${var.name_prefix}-lambda-${var.name_suffix}"
  description = "${var.name_prefix} lambda security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
  egress_with_source_security_group_id = [{
    rule                     = "https-443-tcp"
    source_security_group_id = module.es_security_group[0].security_group_id
    description              = "Log consumer(Lambda) to ES connection"
  }]
}

module "es_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "~> v4.2.0"
  count       = var.use_vpc ? 1 : 0
  name        = "${var.name_prefix}-es-${var.name_suffix}"
  description = "${var.name_prefix} elasticsearch security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
  ingress_with_cidr_blocks = [
    for s in var.public_subnet_cidr_blocks : {
      rule        = "https-443-tcp"
      cidr_blocks = s
      description = "subnet to ESS kibana connection"
    }
  ]
  ingress_with_source_security_group_id = concat([], length(module.lambda_security_group) > 0 ? [{
    rule                     = "https-443-tcp"
    source_security_group_id = module.lambda_security_group[0].security_group_id
    description              = "log consumer(lambda) to ES"
  }] : [], var.consumer_security_group_id != null ? [{
    rule                     = "https-443-tcp"
    source_security_group_id = var.consumer_security_group_id
    description              = "log consumer(lambda) to ES"
  }] : [])
}

resource "aws_elasticsearch_domain" "es" {
  domain_name           = local.es_name
  elasticsearch_version = "7.9"

  cluster_config {
    instance_type            = var.es_node_type
    instance_count           = var.es_node_count
    dedicated_master_enabled = var.es_master_node_count > 0 ? true : false
    dedicated_master_count   = var.es_master_node_count
    dedicated_master_type    = var.es_master_node_type
    zone_awareness_enabled   = var.es_availability_zone_count == 1 ? false : true
    dynamic "zone_awareness_config" {
      for_each = var.es_availability_zone_count > 1 ? [true] : []
      content {
        availability_zone_count = var.es_availability_zone_count
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.es_ebs_volume_size
  }

  dynamic "vpc_options" {
    for_each = var.vpc_id != "" ? [true] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [module.es_security_group[0].security_group_id]
    }
  }

  node_to_node_encryption {
    enabled = var.es_node_to_node_encryption
  }

  encrypt_at_rest {
    enabled = var.es_encrypt_at_rest
  }

  domain_endpoint_options {
    enforce_https                   = true
    tls_security_policy             = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled         = var.use_vpc ? false : true
    custom_endpoint                 = var.kibana_custom_domain
    custom_endpoint_certificate_arn = module.acm.this_acm_certificate_arn
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "admin"
      master_user_password = var.es_master_user_password
    }
    # After apply, go AWS Web Console to create master username/password
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

  tags = var.tags
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
  name = "${var.name_prefix}-${var.name_suffix}"
}

#
# ALB
#
resource "aws_lb" "main" {
  count              = var.use_vpc ? 1 : 0
  name               = "${var.name_prefix}-${var.name_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg[0].id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_listener" "https" {
  count             = length(aws_lb.main)
  load_balancer_arn = aws_lb.main[0].arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = module.acm.this_acm_certificate_arn
  ssl_policy        = var.alb_ssl_policy

  default_action {
    target_group_arn = aws_lb_target_group.main.id
    type             = "forward"
  }
}

resource "aws_lb_listener" "http" {
  count             = length(aws_lb.main)
  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group" "main" {
  name                 = "${var.name_prefix}-${local.container_port}-${var.name_suffix}"
  port                 = local.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 90
  tags                 = var.tags

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

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_lb.main]
}

resource "aws_security_group" "lb_sg" {
  count  = var.use_vpc ? 1 : 0
  name   = "${var.name_prefix}-alb-${var.name_suffix}"
  vpc_id = var.vpc_id
  tags   = var.tags
}

resource "aws_security_group_rule" "app_lb_allow_outbound" {
  count                    = var.use_vpc ? 1 : 0
  security_group_id        = aws_security_group.lb_sg[0].id
  type                     = "egress"
  from_port                = local.container_port
  to_port                  = local.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_sg.id
  description              = "${var.name_prefix} ALB to ECS(proxy for ES Kibana) connection"
}

resource "aws_security_group_rule" "app_lb_allow_all_http" {
  count             = var.use_vpc ? 1 : 0
  security_group_id = aws_security_group.lb_sg[0].id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.service_ingress_cidr_rules
  description       = "${var.name_prefix} ALB service port"
}

resource "aws_security_group_rule" "app_lb_allow_all_https" {
  count             = var.use_vpc ? 1 : 0
  security_group_id = aws_security_group.lb_sg[0].id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.service_ingress_cidr_rules
  description       = "${var.name_prefix} ALB service port"
}

#
# ECS Service
#
module "ecs-service-kibana-proxy" {
  source                        = "trussworks/ecs-service/aws"
  version                       = "~> v6.4.0"
  count                         = var.use_vpc ? 1 : 0
  name                          = var.name_prefix
  environment                   = var.name_suffix
  manage_ecs_security_group     = false
  associate_alb                 = true
  associate_nlb                 = false
  alb_security_group            = aws_security_group.lb_sg[0].id
  additional_security_group_ids = [aws_security_group.ecs_sg.id]
  nlb_subnet_cidr_blocks        = null
  lb_target_groups = [
    {
      lb_target_group_arn         = aws_lb_target_group.main.arn
      container_port              = local.container_port
      container_health_check_port = local.container_port
    },
  ]

  ecs_cluster                 = aws_ecs_cluster.main
  ecs_subnet_ids              = var.public_subnet_ids // TODO: if NAT does exist, private subnets can be used.
  ecs_vpc_id                  = var.vpc_id
  ecs_use_fargate             = true
  assign_public_ip            = true
  kms_key_id                  = aws_kms_key.main.arn
  cloudwatch_alarm_cpu_enable = false
  cloudwatch_alarm_mem_enable = false
  target_container_name       = local.target_container_name
  logs_cloudwatch_group       = local.ecs_log_group_name

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
          "awslogs-group"         = local.ecs_log_group_name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "helloworld"
        }
      }
      environment = [
        { name : "KIBANA_HOST", value : var.kibana_custom_domain },
        { name : "ES_HOST", value : aws_elasticsearch_domain.es.endpoint },
        { name : "AWS_REGION", value : local.region },
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

