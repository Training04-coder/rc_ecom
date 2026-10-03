locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# --- Security group : HTTP/HTTPS publics, pas de SSH (acces via SSM) ---
resource "aws_security_group" "web" {
  name_prefix = "secagent-java-web-"
  description = "Web public pour lab Security Agent"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (redirection + challenge ACME)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Sortant (paquets et Lets Encrypt)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Role IAM minimal : Session Manager uniquement ---
resource "aws_iam_role" "ec2" {
  name_prefix = "secagent-java-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "secagent-java-ec2-"
  role        = aws_iam_role.ec2.name
}

# --- EC2 : Java 21 Corretto + Caddy (HTTPS Let's Encrypt automatique) ---
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true
  credit_specification { cpu_credits = "standard" }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    fqdn      = local.fqdn
    app_java  = file("${path.module}/../app/App.java")
    demo_vuln = var.demo_vuln
  })

  metadata_options {
    http_tokens = "required" # IMDSv2 obligatoire
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "secagent-java-web" }
}

resource "aws_eip" "web" {
  domain   = "vpc"
  instance = aws_instance.web.id
}

# --- DNS : app.mondomaine.tld -> IP elastique ---
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.web.public_ip]
}
