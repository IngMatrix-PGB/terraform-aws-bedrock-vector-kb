# Regression coverage for the correctness bug discovered in PR #3:
# create_s3vectors = false combined with a null/omitted/blank
# s3vectors_index_arn used to crash `terraform plan` with an uncaught
# `trimspace(): argument must not be null` error from the
# use_existing_index local in main.tf, instead of failing cleanly.
#
# The fix (PR #4) is a `validation` block on the `kbs` variable that
# rejects this combination early with a clear, user-facing error, using
# expect_failures to assert against the actual variable being validated
# (not just "some failure happened").
#
# Omitted and explicit `= null` are indistinguishable for an
# optional(string) attribute in Terraform's type system (both evaluate
# to null), so this file does not duplicate a test for both - the
# "omitted" run block below covers both cases.

mock_provider "aws" {
  override_during = plan

  # Required so aws_iam_role.assume_role_policy (which every run below
  # reaches once enabled_kbs is non-empty) gets valid JSON instead of a
  # random mocked string - see create-vector-index.tftest.hcl for details.
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
}

mock_provider "awscc" {
  override_during = plan
}

run "create_s3vectors_false_with_omitted_arn_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors = false
        # s3vectors_index_arn intentionally omitted (evaluates to null).
      }
    }
  }

  expect_failures = [var.kbs]
}

run "create_s3vectors_false_with_empty_string_arn_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = ""
      }
    }
  }

  expect_failures = [var.kbs]
}

run "create_s3vectors_false_with_whitespace_only_arn_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "   "
      }
    }
  }

  expect_failures = [var.kbs]
}

run "create_s3vectors_false_with_valid_arn_still_succeeds" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      valid = {
        kb_name             = "kb-valid"
        role_name           = "kb-valid-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "A valid, non-empty s3vectors_index_arn must still be accepted"
  }
}

run "create_s3vectors_true_with_omitted_arn_still_succeeds" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      created = {
        kb_name             = "kb-created"
        role_name           = "kb-created-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors      = true
        s3vectors_bucket_name = "matrix-vector-nexus-store"
        s3vectors_index_name  = "matrix-vector-nexus-index"
        # s3vectors_index_arn intentionally omitted: not required when creating a new index.
      }
    }
  }

  assert {
    condition     = length(aws_s3vectors_index.this) == 1
    error_message = "create_s3vectors = true must still work without an s3vectors_index_arn"
  }
}
