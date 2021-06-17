#
# SG - ECS
#
resource "aws_security_group" "ecs_sg" {
  name        = "${var.name_prefix}-ecs-${var.name_suffix}"
  description = "${var.name_prefix} ECS container security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "app_ecs_allow_outbound" {
  count             = var.use_vpc ? 1 : 0
  description       = "${var.name_prefix} ECS Continaer to ESS Kibana"
  security_group_id = aws_security_group.ecs_sg.id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app_ecs_allow_https_from_alb" {
  # if we have an alb, then create security group rules for the container
  # ports
  count                    = var.use_vpc ? 1 : 0
  description              = "${var.name_prefix} ALB to ECS Container"
  security_group_id        = aws_security_group.ecs_sg.id
  type                     = "ingress"
  from_port                = local.container_port
  to_port                  = local.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg[0].id
}
