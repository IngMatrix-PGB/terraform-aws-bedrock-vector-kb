# Coverage for the confused-deputy / partition / bucket-ownership hardening:
#   - the S3 read policy is partition-aware (built from data.aws_partition,
#     not a hardcoded "arn:aws") and pinned to this account via
#     aws:ResourceAccount, since S3 bucket names are global
#   - the documents bucket has ACLs disabled (BucketOwnerEnforced)
#   - content_bucket_arns exposes the documents bucket ARN per KB
#
# The trust policy's aws:SourceAccount/aws:SourceArn conditions are NOT
# asserted here: under mock_provider, aws_iam_policy_document's .json is
# mocked per type (see docs-bucket-hardening.tftest.hcl for the full
# explanation), so asserting its content would only test the mock.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Action    = "sts:AssumeRole"
          Principal = { Service = "bedrock.amazonaws.com" }
        }]
      })
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws-us-gov"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws-us-gov:s3:::mock-bucket"
    }
  }
}

mock_provider "awscc" {
  override_during = plan
}

variables {
  enable_kbs = true
  tags       = {}
  kbs = {
    a = {
      kb_name             = "kb-a"
      role_name           = "kb-a-role"
      embedding_model_arn = "arn:aws-us-gov:bedrock:us-gov-west-1::foundation-model/amazon.titan-embed-text-v2:0"
      content_bucket      = "bucket-a"
      content_prefix      = "docs/"

      create_s3vectors    = false
      s3vectors_index_arn = "arn:aws-us-gov:s3vectors:us-gov-west-1:123456789012:bucket/one/index/one"
    }
  }
}

run "s3_read_policy_uses_the_current_partition" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_read["a"].policy).Statement[0].Resource[0] == "arn:aws-us-gov:s3:::bucket-a"
    error_message = "s3:ListBucket must be scoped to the bucket ARN in the current partition, not a hardcoded arn:aws"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_read["a"].policy).Statement[1].Resource[0] == "arn:aws-us-gov:s3:::bucket-a/docs/*"
    error_message = "s3:GetObject must be scoped to bucket + prefix in the current partition, not a hardcoded arn:aws"
  }
}

run "s3_read_policy_is_pinned_to_this_account" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.kb_s3_read["a"].policy).Statement :
      s.Condition.StringEquals["aws:ResourceAccount"] == "123456789012"
    ])
    error_message = "Every S3 read statement must carry aws:ResourceAccount = this account, so a same-named bucket in another account never matches"
  }
}

run "docs_bucket_disables_acls" {
  command = plan

  assert {
    condition     = aws_s3_bucket_ownership_controls.kb_docs["a"].rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "The documents bucket must use BucketOwnerEnforced (ACLs disabled)"
  }
}

run "content_bucket_arns_exposes_the_docs_bucket" {
  command = plan

  assert {
    condition     = output.content_bucket_arns["a"] == "arn:aws-us-gov:s3:::mock-bucket"
    error_message = "content_bucket_arns must return the documents bucket ARN for each KB"
  }
}
