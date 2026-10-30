locals {
  fqdn        = "${var.subdomain}.${var.domain_name}"
  name_prefix = "${var.initials}-secagent-java"
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
  name_prefix = "${local.name_prefix}-web-"
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

  tags = { Name = "${local.name_prefix}-web" }
}

# --- Role IAM minimal : Session Manager + lecture S3 + ecriture CloudWatch Logs ---
resource "aws_iam_role" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ec2" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3_read" {
  name = "${var.initials}-lecture-code-app"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.app.arn },
      { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.app.arn}/*" },
    ]
  })
}

# Sauvegarde/restauration des certificats Caddy sous le prefixe caddy/ du bucket
# (lecture deja couverte par s3_read ; ici on ajoute l'ecriture)
resource "aws_iam_role_policy" "caddy_certs" {
  name = "${var.initials}-sauvegarde-certs-caddy"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.app.arn}/caddy/*"
    }]
  })
}

# Droits minimaux CloudWatch Logs, restreints au seul log group /rch-bricoshop/app
resource "aws_iam_role_policy" "cw_logs" {
  name = "${var.initials}-ecriture-logs-cloudwatch"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.app.arn,
        "${aws_cloudwatch_log_group.app.arn}:*",
      ]
    }]
  })
}

# --- CloudWatch Logs : destination des logs applicatifs ---
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.initials}-bricoshop/app"
  retention_in_days = 30

  tags = { Name = "${var.initials}-bricoshop-app" }
}

# --- S3 prive : code de l'appli (App.java + static/), telecharge par l'EC2 au demarrage ---
locals {
  app_files = merge(
    { "App.java" = "${path.module}/../app/App.java" },
    { for f in fileset("${path.module}/../app/static", "*") : "static/${f}" => "${path.module}/../app/static/${f}" },
  )
  # Empreinte du code : inseree dans le user_data pour recreer l'instance a chaque changement de code
  app_hash = sha1(join(",", [for k, p in local.app_files : "${k}:${filesha1(p)}"]))
}

resource "aws_s3_bucket" "app" {
  bucket_prefix = "${local.name_prefix}-app-"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-app" }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "app" {
  for_each = local.app_files
  bucket   = aws_s3_bucket.app.id
  key      = each.key
  source   = each.value
  etag     = filemd5(each.value)
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-"
  role        = aws_iam_role.ec2.name

  tags = { Name = "${local.name_prefix}-ec2" }
}

# --- EC2 : Java 21 Corretto + Caddy (HTTPS Let's Encrypt automatique) ---
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true
  credit_specification { cpu_credits = "standard" }

  # Le code vient de S3 (plus de limite de 16 Ko). replace() retire les CRLF d'un checkout Windows.
  user_data = replace(templatefile("${path.module}/user_data.sh.tftpl", {
    fqdn      = local.fqdn
    bucket    = aws_s3_bucket.app.id
    region    = var.aws_region
    app_hash  = local.app_hash
    log_group = aws_cloudwatch_log_group.app.name
    demo_vuln = var.demo_vuln
  }), "\r\n", "\n")

  # Code, droits et log group doivent exister avant le demarrage de l'instance
  depends_on = [aws_s3_object.app, aws_iam_role_policy.s3_read, aws_iam_role_policy.cw_logs, aws_cloudwatch_log_group.app]

  metadata_options {
    http_tokens = "required" # IMDSv2 obligatoire
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${local.name_prefix}-web" }
}

resource "aws_eip" "web" {
  domain   = "vpc"
  instance = aws_instance.web.id

  tags = { Name = "${local.name_prefix}-eip" }
}

# --- DNS : rch.alpha-awslab26.click -> IP elastique ---
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.web.public_ip]
}
