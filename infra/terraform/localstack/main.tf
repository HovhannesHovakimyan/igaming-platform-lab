# AWS resources in LocalStack, reached through the edge Gateway.
# LocalStack keeps state in memory: after its pod restarts, run `task localstack` again.

terraform {
  required_version = ">= 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }
}

variable "endpoint" {
  description = "LocalStack endpoint."
  type        = string
  default     = "https://localstack.igaming.lab"
}

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3             = var.endpoint
    secretsmanager = var.endpoint
    kms            = var.endpoint
    sqs            = var.endpoint
    sts            = var.endpoint
    iam            = var.endpoint
  }

  default_tags {
    tags = {
      project    = "igaming-platform-lab"
      managed-by = "terraform"
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "Encrypts lab buckets and secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "platform" {
  name          = "alias/igaming-platform"
  target_key_id = aws_kms_key.platform.key_id
}

# Database and cluster backups (Phase 3, Phase 9) and KYC document uploads.
locals {
  buckets = toset(["igaming-lab-backups", "igaming-lab-kyc-documents"])
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = each.key
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Read by the platform-smoke ExternalSecret to prove the secret pipeline works.
resource "aws_secretsmanager_secret" "smoke" {
  name                    = "igaming/platform/smoke"
  kms_key_id              = aws_kms_key.platform.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "smoke" {
  secret_id     = aws_secretsmanager_secret.smoke.id
  secret_string = jsonencode({ message = "hello from LocalStack Secrets Manager" })
}

output "buckets" {
  value = [for b in aws_s3_bucket.this : b.id]
}
