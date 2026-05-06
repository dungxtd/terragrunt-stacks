# TF-managed ALB. Replaces controller-managed Ingress so destroy is clean.
# k8s TargetGroupBinding (CR from aws-load-balancer-controller) registers
# pod IPs to this TF-owned target group. Controller never creates the LB.

locals {
  https_enabled = var.certificate_arn != ""
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "ALB ingress for ${var.project}"
  vpc_id      = var.vpc_id

  ingress {
    description = "Listener port from internet"
    from_port   = var.listen_port
    to_port     = var.listen_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-alb" })
}

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = var.scheme == "internal"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  tags = var.tags
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project}-frontend"
  port        = var.service_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.listen_port
  protocol          = local.https_enabled ? "HTTPS" : "HTTP"
  ssl_policy        = local.https_enabled ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = local.https_enabled ? var.certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = var.tags
}

# TargetGroupBinding CR — controller registers pods of <service> to <TG>.
# CRD provided by aws-load-balancer-controller (installed by aws-alb unit).
resource "kubernetes_manifest" "target_group_binding" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = var.service_name
      namespace = var.service_namespace
    }
    spec = {
      serviceRef = {
        name = var.service_name
        port = var.service_port
      }
      targetGroupARN = aws_lb_target_group.frontend.arn
    }
  }
}
