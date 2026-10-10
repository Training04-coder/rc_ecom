data "aws_caller_identity" "current" {}

# Echoue des le bootstrap si la zone du participant n'existe pas dans son compte.
data "aws_route53_zone" "site" {
  name         = var.domain_name
  private_zone = false
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  subject_base = "repo:${var.github_owner}/${var.github_repo}"
  audience     = "sts.amazonaws.com"
  oidc_host    = "token.actions.githubusercontent.com"
  oidc_arn     = "arn:aws:iam::${local.account_id}:oidc-provider/${local.oidc_host}"

  # Conventions partagees avec .github/workflows/deploy.yml : le workflow
  # reconstruit ces noms a partir de vars.AWS_ACCOUNT_ID. Ne pas les changer seuls.
  state_bucket     = "bricoshop-tfstate-${local.account_id}"
  role_plan_name   = "github-actions-plan"
  role_deploy_name = "github-actions-deploy"
  environment      = "production"

  # Ressources du Terraform principal (name_prefix / bucket_prefix => suffixe
  # aleatoire inconnu, d'ou les wildcards sur le prefixe).
  app_bucket_arn  = "arn:aws:s3:::secagent-java-app-*"
  ec2_role_arn    = "arn:aws:iam::${local.account_id}:role/secagent-java-ec2-*"
  ec2_profile_arn = "arn:aws:iam::${local.account_id}:instance-profile/secagent-java-ec2-*"
  log_group_arn   = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/bricoshop/app"
  zone_arn        = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.site.zone_id}"
}

# ---------------------------------------------------------------------------
# 1) Fournisseur OIDC : etablit la confiance GitHub Actions -> AWS STS.
#    Un seul par compte : create_oidc_provider = false pour reutiliser l'existant.
#    thumbprint_list omis : le provider AWS >= 5 le calcule.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = [local.audience]
}

# ---------------------------------------------------------------------------
# 2) Bucket S3 du state Terraform : versioning + chiffrement + prive.
#    force_destroy : lab de formation, pour que le nettoyage final passe.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket
  force_destroy = true
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
#     Lecture seule + lecture du state (le plan tourne avec -lock=false).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust_plan" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
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
  name                 = local.role_plan_name
  description          = "GitHub Actions : terraform plan depuis les PR (lecture seule)"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600

  # La trust policy reference le fournisseur OIDC : il doit exister avant.
  depends_on = [aws_iam_openid_connect_provider.github]
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
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.subject_base}:environment:${local.environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = local.role_deploy_name
  description          = "GitHub Actions : terraform apply depuis l'environnement ${local.environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust_deploy.json
  max_session_duration = 3600

  depends_on = [aws_iam_openid_connect_provider.github]
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
        Resource = local.zone_arn
      },
    ]
  })
}
