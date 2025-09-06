data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_repos  = ["platform-api", "llm-inference", "jobs-worker"]
}

# ---------- ECR repositories ----------
resource "aws_ecr_repository" "repos" {
  for_each = toset(local.ecr_repos)
  name     = "${var.project}/${each.key}" # e.g. llm-saas/platform-api

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" } # AWS-managed KMS key
  force_delete = true

  tags = { Project = var.project, Environment = var.environment }
}

# Keep only recent images per repo (optional but handy)
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1, description = "keep last 15 tagged",
      selection    = { tagStatus = "tagged", tagPrefixList = ["latest"], countType = "imageCountMoreThan", countNumber = 15 },
      action       = { type = "expire" }
    }]
  })
}

# ---------- GitHub OIDC provider ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Standard GitHub Actions OIDC thumbprint (current). If AWS errors later, update this.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy so a specific repo (and branches/tags) can assume the role
data "aws_iam_policy_document" "gha_assume" {
  statement {
    sid     = "GithubOIDCAssume"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Allow all refs in your repo initially. You can narrow later (e.g., refs/heads/main)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:randi2160/llm-saas:ref:refs/heads/main",
        "repo:randi2160/llm-saas:ref:refs/tags/v*",
      ]
    }
  }
}

# Role GitHub Actions will assume to push to ECR
resource "aws_iam_role" "gha_ecr" {
  name               = "${var.project}-${var.environment}-gha-ecr"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
  tags               = { Project = var.project, Environment = var.environment }
}

# Least-privilege policy to push/pull on our repos
data "aws_iam_policy_document" "gha_ecr_push" {
  # GetAuthorizationToken must be "*"
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  # Push/pull specific repos only
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:ListImages"
    ]
    resources = [for r in aws_ecr_repository.repos : r.arn]
  }
}

resource "aws_iam_policy" "gha_ecr_push" {
  name   = "${var.project}-${var.environment}-gha-ecr-push"
  policy = data.aws_iam_policy_document.gha_ecr_push.json
}

resource "aws_iam_role_policy_attachment" "gha_ecr_attach" {
  role       = aws_iam_role.gha_ecr.name
  policy_arn = aws_iam_policy.gha_ecr_push.arn
}

# ---------- Outputs ----------
output "ecr_repo_urls" {
  value = { for k, r in aws_ecr_repository.repos : k => r.repository_url }
}

output "gha_role_arn" {
  value = aws_iam_role.gha_ecr.arn
}