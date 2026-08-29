# Coverage for PR #6 docs-bucket hardening: TLS-only access, lifecycle
# (multipart cleanup always on, noncurrent-version expiration opt-in only),
# optional SSE-KMS, and optional access logging.
#
# All scenarios use create_s3vectors = false with an external index ARN,
# since these features only concern the documents bucket and are
# independent of the S3 Vectors create/existing-index mode (already
# covered by the other test files).
#
# Note on scope: this file asserts that the TLS-deny bucket policy exists
# and is attached to the correct documents bucket (module behavior). It
# deliberately does NOT assert the exact JSON content of the policy (e.g.
# the Deny/SecureTransport condition): under mock_provider,
# aws_iam_policy_document's .json is mocked per TYPE, not per data source
# label, so this file's own kb_docs_tls_only data source would share the
# same mocked default as the unrelated bedrock_kb_assume trust policy
# data source elsewhere in the module - asserting its content here would
# only be testing the mock, not our HCL. Verifying the actual policy JSON
# shape is a provider-implementation-level concern outside what native
# terraform test can assert without real AWS credentials; it was verified
# manually during implementation instead (see PR #6 report).

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

  # Needed for the bucket-wiring assertion below (aws_s3_bucket.kb_docs.id
  # is otherwise "(known after apply)" at plan time).
  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "mock-bucket"
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

mock_provider "awscc" {
  override_during = plan
}

variables {
  enable_kbs = true
  tags       = {}
}

run "tls_only_policy_and_lifecycle_are_always_present" {
  command = plan

  variables {
    kbs = {
      hardened = {
        kb_name             = "kb-hardened"
        role_name           = "kb-hardened-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_policy.kb_docs_tls_only) == 1
    error_message = "Expected exactly one TLS-only bucket policy to always be planned"
  }

  assert {
    condition     = aws_s3_bucket_policy.kb_docs_tls_only["hardened"].bucket == aws_s3_bucket.kb_docs["hardened"].id
    error_message = "The TLS-only bucket policy must be attached to this KB's own documents bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.kb_docs) == 1
    error_message = "Expected exactly one lifecycle configuration to always be planned"
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule : r.abort_incomplete_multipart_upload[0].days_after_initiation if r.id == "abort-incomplete-multipart-uploads"][0] == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule) == 1
    error_message = "By default (no noncurrent_version_expiration_days), only the multipart-cleanup rule should be planned - noncurrent-version deletion must never be a default"
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule : r if r.id == "expire-noncurrent-versions"]) == 0
    error_message = "The noncurrent-version-expiration rule must be absent unless noncurrent_version_expiration_days is explicitly set"
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.kb_docs["hardened"].rule : r.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "AES256"
    error_message = "Default encryption must remain SSE-S3 (AES256) when no kms_key_arn is supplied"
  }

  assert {
    condition     = length(aws_iam_policy.kb_s3_kms) == 0
    error_message = "No KMS IAM policy should be planned when kms_key_arn is not supplied"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.kb_docs) == 0
    error_message = "No access logging should be planned when logging_target_bucket is not supplied"
  }
}

run "kms_key_arn_switches_encryption_and_grants_scoped_iam_access" {
  command = plan

  variables {
    kbs = {
      hardened = {
        kb_name             = "kb-hardened"
        role_name           = "kb-hardened-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"

        kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
      }
    }
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.kb_docs["hardened"].rule : r.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "aws:kms"
    error_message = "Encryption must switch to aws:kms when kms_key_arn is supplied"
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.kb_docs["hardened"].rule : r.apply_server_side_encryption_by_default[0].kms_master_key_id][0] == "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
    error_message = "kms_master_key_id must equal the supplied kms_key_arn"
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.kb_docs["hardened"].rule : r.bucket_key_enabled][0] == true
    error_message = "S3 Bucket Keys should be enabled when using KMS, to reduce KMS request costs"
  }

  assert {
    condition     = length(aws_iam_policy.kb_s3_kms) == 1
    error_message = "A KMS IAM policy must be planned when kms_key_arn is supplied"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_kms["hardened"].policy).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
    error_message = "The KMS IAM policy must be scoped to exactly the supplied kms_key_arn"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.s3_kms) == 1
    error_message = "The KMS IAM policy must be attached to the KB role"
  }
}

run "noncurrent_version_expiration_days_configures_opt_in_retention" {
  command = plan

  variables {
    kbs = {
      hardened = {
        kb_name             = "kb-hardened"
        role_name           = "kb-hardened-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"

        noncurrent_version_expiration_days = 45
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule) == 2
    error_message = "Both the multipart-cleanup rule and the opt-in noncurrent-version rule should be planned"
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule : r.noncurrent_version_expiration[0].noncurrent_days if r.id == "expire-noncurrent-versions"][0] == 45
    error_message = "noncurrent_version_expiration_days must control the actual retention value used"
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.kb_docs["hardened"].rule : r.abort_incomplete_multipart_upload[0].days_after_initiation if r.id == "abort-incomplete-multipart-uploads"][0] == 7
    error_message = "The multipart-cleanup rule must still be present regardless of the noncurrent-version opt-in"
  }
}

run "noncurrent_version_expiration_days_zero_is_rejected" {
  command = plan

  variables {
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"
        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"

        noncurrent_version_expiration_days = 0
      }
    }
  }

  expect_failures = [var.kbs]
}

run "logging_target_bucket_enables_access_logging" {
  command = plan

  variables {
    kbs = {
      hardened = {
        kb_name             = "kb-hardened"
        role_name           = "kb-hardened-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"

        logging_target_bucket = "my-external-logs-bucket"
        logging_target_prefix = "kb-docs/"
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_logging.kb_docs) == 1
    error_message = "Access logging must be planned when logging_target_bucket is supplied"
  }

  assert {
    condition     = aws_s3_bucket_logging.kb_docs["hardened"].target_bucket == "my-external-logs-bucket"
    error_message = "target_bucket must equal the supplied logging_target_bucket"
  }

  assert {
    condition     = aws_s3_bucket_logging.kb_docs["hardened"].target_prefix == "kb-docs/"
    error_message = "target_prefix must equal the supplied logging_target_prefix"
  }
}

run "kms_key_arn_empty_string_is_rejected" {
  command = plan

  variables {
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"
        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
        kms_key_arn         = "   "
      }
    }
  }

  expect_failures = [var.kbs]
}

run "logging_target_bucket_empty_string_is_rejected" {
  command = plan

  variables {
    kbs = {
      broken = {
        kb_name               = "kb-broken"
        role_name             = "kb-broken-role"
        embedding_model_arn   = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket        = "matrix-bedrock-documents"
        create_s3vectors      = false
        s3vectors_index_arn   = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
        logging_target_bucket = ""
      }
    }
  }

  expect_failures = [var.kbs]
}
