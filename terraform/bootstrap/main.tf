data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  subject_base = "repo:${var.github_org}/${var.github_repo}"
  state_bucket = var.state_bucket_name != "" ? var.state_bucket_name : lower("${var.github_org}-${var.github_repo}-tfstate")
  audience     = "sts.amazonaws.com"
  oidc_host    = "token.actions.githubusercontent.com"

  # ARN des ressources gerees par le Terraform principal (name_prefix / bucket_prefix
  # => on ne connait pas le suffixe aleatoire, d'ou les wildcards sur le prefixe).
  app_bucket_arn   = "arn:aws:s3:::${var.managed_resource_prefix}app-*"
  ec2_role_arn     = "arn:aws:iam::${local.account_id}:role/${var.managed_resource_prefix}ec2-*"
  ec2_profile_arn  = "arn:aws:iam::${local.account_id}:instance-profile/${var.managed_resource_prefix}ec2-*"
  log_group_arn    = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:${var.app_log_group_name}"
  route53_resource = var.route53_zone_id != "" ? "arn:aws:route53:::hostedzone/${var.route53_zone_id}" : "*"
}

# ---------------------------------------------------------------------------
# 1) Fournisseur OIDC : etablit la confiance GitHub Actions -> AWS STS.
#    thumbprint_list omis volontairement : le provider AWS >= 5 le calcule, et
#    AWS securise desormais ce fournisseur via sa propre librairie de confiance.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = [local.audience]
}

# ---------------------------------------------------------------------------
# 2) Bucket S3 du state Terraform : versioning + chiffrement + prive.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# 3a) Role PLAN : assumable UNIQUEMENT depuis les pull requests du depot.
#     Lecture seule + acces au bucket de state (lecture/ecriture du lockfile).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust_plan" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.subject_base}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-plan"
  description          = "GitHub Actions : terraform plan depuis les PR (lecture seule)"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Acces minimal au bucket de state pour le refresh du plan.
resource "aws_iam_role_policy" "plan_state" {
  name = "acces-state-plan"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# 3b) Role DEPLOY : assumable UNIQUEMENT depuis l'environnement GitHub cible.
#     Moindre privilege : seules les actions des services reellement utilises.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust_deploy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.subject_base}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "github-actions-deploy"
  description          = "GitHub Actions : terraform apply depuis l'environnement ${var.github_environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust_deploy.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy_state" {
  name = "acces-state-deploy"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "ReadWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
    ]
  })
}

# Politique "infrastructure" : scopée aux services et ARN du Terraform principal.
resource "aws_iam_role_policy" "deploy_infra" {
  name = "infra-moindre-privilege"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2DescribeReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = "*"
      },
      {
        # EC2/SG/EIP/volumes : la plupart des actions mutantes EC2 ne supportent
        # pas le scoping par ARN, d'ou Resource "*" borne par la liste d'actions.
        Sid    = "Ec2Manage"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyInstanceMetadataOptions",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress",
        ]
        Resource = "*"
      },
      {
        Sid    = "IamManageProjectRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
        ]
        Resource = local.ec2_role_arn
      },
      {
        Sid    = "IamManageInstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
        ]
        Resource = local.ec2_profile_arn
      },
      {
        # PassRole restreint au role EC2 du projet ET au seul service EC2.
        Sid      = "IamPassRoleToEc2"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = local.ec2_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        # Seules les policies managees AWS autorisees a etre attachees au role EC2.
        Sid      = "IamAllowOnlySsmManagedPolicy"
        Effect   = "Allow"
        Action   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]
        Resource = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      },
      {
        Sid    = "S3AppBucket"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          local.app_bucket_arn,
          "${local.app_bucket_arn}/*",
        ]
      },
      {
        Sid    = "CloudWatchLogsAppGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:ListTagsLogGroup",
        ]
        Resource = [
          local.log_group_arn,
          "${local.log_group_arn}:*",
        ]
      },
      {
        Sid    = "Route53ReadZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
          "route53:GetChange",
        ]
        Resource = "*"
      },
      {
        Sid      = "Route53ChangeRecords"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = local.route53_resource
      },
    ]
  })
}
