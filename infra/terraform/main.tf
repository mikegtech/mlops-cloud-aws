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

module "multi_inventory_configurations_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${local.name}-data-catalog-${var.deploy_env}"

  force_destroy = true

  attach_policy                       = true
  attach_inventory_destination_policy = true
  inventory_self_source_destination   = true

  versioning = {
    status     = true
    mfa_delete = false
  }

  inventory_configuration = {

    # Same source and destination buckets
    daily = {
      included_object_versions = "Current"
      destination = {
        format = "CSV"
        encryption = {
          encryption_type = "sse_kms"
          kms_key_id      = module.kms.key_arn
        }
      }
      filter = {
        prefix = "documents/"
      }
      frequency = "Daily"
    }

    weekly = {
      included_object_versions = "All"
      destination = {
        format = "CSV"
      }
      frequency = "Weekly"
    }

    # Different destination bucket
    destination_other = {
      included_object_versions = "All"
      destination = {
        bucket_arn = module.inventory_destination_bucket.s3_bucket_arn
        format     = "Parquet"
        encryption = {
          encryption_type = "sse_s3"
        }
      }
      frequency       = "Weekly"
      optional_fields = ["Size", "EncryptionStatus", "StorageClass", "ChecksumAlgorithm"]
    }

    # Different source bucket
    source_other = {
      included_object_versions = "Current"
      bucket                   = module.inventory_source_bucket.s3_bucket_id
      destination = {
        format = "ORC"
        encryption = {
          encryption_type = "sse_s3"
        }
      }
      frequency = "Daily"
    }
  }
}

resource "random_pet" "this" {
  length = 2
}

# https://docs.aws.amazon.com/AmazonS3/latest/userguide/configure-inventory.html#configure-inventory-kms-key-policy
module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "Key example for Inventory S3 destination encyrption"
  deletion_window_in_days = 7
  key_statements = [
    {
      sid = "s3InventoryPolicy"
      actions = [
        "kms:GenerateDataKey",
      ]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["s3.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values = [
            data.aws_caller_identity.current.id,
          ]
        },
        {
          test     = "ArnLike"
          variable = "aws:SourceARN"
          values = [
            module.inventory_source_bucket.s3_bucket_arn,
            module.multi_inventory_configurations_bucket.s3_bucket_arn
          ]
        }
      ]
    }
  ]
}

module "inventory_destination_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                              = "inventory-destination-${var.deploy_env}-${random_pet.this.id}"
  force_destroy                       = true
  attach_policy                       = true
  attach_inventory_destination_policy = true
  inventory_source_bucket_arn         = module.multi_inventory_configurations_bucket.s3_bucket_arn
  inventory_source_account_id         = data.aws_caller_identity.current.id
}

module "inventory_source_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket        = "inventory-source-${var.deploy_env}-${random_pet.this.id}"
  force_destroy = true
}

#---------------------------------------------------------------
# Create the dedicated table bucket for storing queryable metadata
#---------------------------------------------------------------
module "multi_inventory_queryable_meta_configurations_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${local.name}-data-catalog-metadata-bucket-${var.deploy_env}"
  versioning = {
    status     = true
    mfa_delete = false
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.objects.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

####################################
# Define a Namespace for Metadata  #
####################################

resource "aws_s3tables_namespace" "metadata_namespace" {
  namespace        = "${local.name}-data-catalog-metadata-namespace"
  table_bucket_arn = multi_inventory_queryable_meta_configurations_bucket.metadata_bucket.arn
}

####################################
# Create the Queryable Metadata Table
####################################

resource "aws_s3tables_table" "metadata_table" {
  name             = "${local.name}-data-catalog-queryable-${var.deploy_env}"
  namespace        = aws_s3tables_namespace.metadata_namespace.namespace
  table_bucket_arn = aws_s3tables_namespace.metadata_namespace.table_bucket_arn
  format           = "ICEBERG"
}

####################################
# Source Data Bucket Configuration #
####################################
module "multi_inventory_queryable_configurations_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${local.name}-data-catalog-bucket-${var.deploy_env}"
  versioning = {
    status     = true
    mfa_delete = false
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.objects.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Enable S3 Metadata for the source bucket
resource "aws_s3_bucket_metadata" "source_bucket_metadata" {
  bucket = multi_inventory_queryable_configurations_bucket.s3_bucket_id

  metadata_configuration {
    metadata_table {
      table_arn = aws_s3tables_table.metadata_table.arn
      enabled   = true
    }
  }
}

# IAM role for S3 to write to metadata tables
resource "aws_iam_role" "s3_metadata_role" {
  name = "s3-metadata-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy to allow S3 to write to metadata tables
resource "aws_iam_role_policy" "s3_metadata_policy" {
  name = "s3-metadata-policy"
  role = aws_iam_role.s3_metadata_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3tables_table_bucket.metadata_bucket.arn,
          "${aws_s3tables_table_bucket.metadata_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3tables:WriteTable"
        ]
        Resource = aws_s3tables_table.metadata_table.arn
      }
    ]
  })
}
