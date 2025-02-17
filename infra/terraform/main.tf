terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.61.0, < 6.0.0"
    }
    github = {
      source  = "integrations/github"
      version = "5.42.0"
    }
  }
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.aws_region
  # default tags per https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags-configuration-block
  default_tags {
    tags = {
      requester = var.requester_name
      env       = var.deploy_env
      ManagedBy = "Terraform"
    }
  }
}

# for github secrets creation
provider "github" {
  token = var.pipeline_token
  owner = var.github_repo_owner
}

################################################################################
# Supporting Resources
################################################################################
data "aws_ssm_parameter" "cert" {
  name = "/base/certificateArn"
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  name = var.vpc_name

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
}

module "mlops-data-catalog" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "${local.name}-data-"
  bucket        = "catalog-directory"
  is_directory_bucket = false

  availability_zone_id = data.aws_availability_zones.available.zone_ids[1]
  server_side_encryption_configuration = {
    rule = {
      bucket_key_enabled = true # required for directory buckets
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.objects.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
  lifecycle_rule = [
    {
      id     = "test"
      status = "Enabled"
      expiration = {
        days = 7
      }
    },
    {
      id     = "logs"
      status = "Enabled"
      expiration = {
        days = 5
      }
      filter = {
        prefix                = "logs/"
        object_size_less_than = 10
      }
    },
    {
      id     = "other"
      status = "Enabled"
      expiration = {
        days = 2
      }
      filter = {
        prefix = "other/"
      }
    }
  ]
  attach_policy = true
  policy        = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_kms_key" "objects" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}

data "aws_iam_policy_document" "bucket_policy" {

  statement {
    sid    = "ReadWriteAccess"
    effect = "Allow"

    actions = [
      "s3express:CreateSession",
    ]

    resources = [module.mlops-data-catalog.s3_directory_bucket_arn]

    principals {
      identifiers = [data.aws_caller_identity.current.account_id]
      type        = "AWS"
    }
  }

  statement {
    sid    = "ReadOnlyAccess"
    effect = "Allow"

    actions = [
      "s3express:CreateSession",
    ]

    resources = [module.mlops-data-catalog.s3_directory_bucket_arn]

    principals {
      identifiers = [data.aws_caller_identity.current.account_id]
      type        = "AWS"
    }

    condition {
      test     = "StringEquals"
      values   = ["ReadOnly"]
      variable = "s3express:SessionMode"
    }
  }
}