# Coverage for PR #18: optional S3 Vectors SSE-KMS encryption
# (s3vectors_kms_key_arn), wired identically onto both
# aws_s3vectors_vector_bucket.this and aws_s3vectors_index.this, plus the
# new, separate aws_iam_policy.s3vectors_kms IAM policy (kms:Decrypt only,
# scoped to the supplied key ARN).
#
# Scope: only create_s3vectors = true scenarios exercise this field - an
# externally-provided s3vectors_index_arn (create_s3vectors = false) has no
# module-created aws_s3vectors_vector_bucket/aws_s3vectors_index to attach
# encryption_configuration to, so s3vectors_kms_key_arn has no effect there
# (not separately covered here; see tests/existing-vector-index.tftest.hcl
# for that mode's own coverage, which is unaffected by this PR).
#
# Mock limitations (per PR #18 discovery): these mocked terraform test runs
# prove Terraform HCL shape only - conditional dynamic blocks, exact
# kms_key_arn/sse_type wiring, IAM policy JSON shape and scoping, map
# cardinality across multiple kbs entries, and regression behavior of
# every other output/resource. They do NOT and cannot prove:
#   - that AWS actually accepts the supplied CMK for a real
#     CreateVectorBucket/CreateIndex call,
#   - that the CMK's own key policy actually grants
#     aws_iam_role.bedrock_kb kms:Decrypt (this module only creates the
#     IAM-side grant; the key policy itself remains external/BYO, exactly
#     like the pre-existing docs-bucket kms_key_arn),
#   - that kms:Decrypt alone (without kms:GenerateDataKey or any other
#     action) is sufficient for the complete Bedrock -> S3 Vectors write
#     path in practice. AWS's own encryption documentation names only
#     kms:Decrypt as necessary, and no AWS source found names any
#     additional action, so none is granted speculatively - but AWS does
#     not explicitly state that kms:Decrypt alone is sufficient for
#     writes either. This is a residual, flagged ambiguity, not a
#     resolved one - see the README's "S3 Vectors Encryption" section.
#     Live AWS integration validation remains future work.
#   - that a real apply against an existing, unencrypted vector
#     bucket/index actually replaces it as AWS documents (encryption
#     settings "can't be changed after the vector bucket/index is
#     created") - that replacement/data-loss behavior is a live-AWS
#     concern outside what a mocked plan can exercise. Whether that
#     replacement also cascades to the Knowledge Base/Data Source (the
#     Knowledge Base's storage_configuration is a CloudFormation
#     create-only property) is likewise unverified against a live plan -
#     see the README's "S3 Vectors Encryption" section.

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

  # encryption_configuration is optional+computed in the provider schema:
  # when this module's dynamic block emits nothing (s3vectors_kms_key_arn
  # omitted), it is otherwise "(known after apply)" at plan time even
  # under the provider-level override_during = plan. Defaulting it to an
  # empty list here tests exactly what this module's own HCL controls
  # (whether the dynamic block emits a block at all) - it does not claim
  # to simulate AWS's own real computed default for an unencrypted
  # bucket/index.
  mock_resource "aws_s3vectors_index" {
    defaults = {
      index_arn                = "arn:aws:s3vectors:us-east-1:123456789012:bucket/mock-vector-bucket/index/mock-vector-index"
      encryption_configuration = []
    }
  }

  mock_resource "aws_s3vectors_vector_bucket" {
    defaults = {
      encryption_configuration = []
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

mock_provider "awscc" {
  override_during = plan

  mock_resource "awscc_bedrock_data_source" {
    defaults = {
      data_source_configuration = {
        s3_configuration = {
          inclusion_prefixes = []
        }
      }
    }
  }
}

variables {
  enable_kbs = true
  tags       = {}
}

run "default_omitted_produces_no_encryption_configuration_and_no_kms_iam" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        # s3vectors_kms_key_arn intentionally omitted (defaults to null).
      }
    }
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this["a"].encryption_configuration) == 0
    error_message = "Omitting s3vectors_kms_key_arn must produce zero encryption_configuration blocks on the vector bucket"
  }

  assert {
    condition     = length(aws_s3vectors_index.this["a"].encryption_configuration) == 0
    error_message = "Omitting s3vectors_kms_key_arn must produce zero encryption_configuration blocks on the vector index"
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 0
    error_message = "No S3 Vectors KMS IAM policy should be planned when s3vectors_kms_key_arn is not supplied"
  }
}

run "s3vectors_kms_key_arn_produces_exact_encryption_configuration_on_bucket_and_index" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        s3vectors_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock-vectors-key"
      }
    }
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this["a"].encryption_configuration) == 1
    error_message = "Setting s3vectors_kms_key_arn must produce exactly one encryption_configuration block on the vector bucket"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].sse_type == "aws:kms"
    error_message = "sse_type must be exactly aws:kms on the vector bucket when s3vectors_kms_key_arn is set"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mock-vectors-key"
    error_message = "The vector bucket's encryption_configuration.kms_key_arn must equal the supplied s3vectors_kms_key_arn"
  }

  assert {
    condition     = length(aws_s3vectors_index.this["a"].encryption_configuration) == 1
    error_message = "Setting s3vectors_kms_key_arn must produce exactly one encryption_configuration block on the vector index"
  }

  assert {
    condition     = aws_s3vectors_index.this["a"].encryption_configuration[0].sse_type == "aws:kms"
    error_message = "sse_type must be exactly aws:kms on the vector index when s3vectors_kms_key_arn is set"
  }

  assert {
    condition     = aws_s3vectors_index.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mock-vectors-key"
    error_message = "The vector index's encryption_configuration.kms_key_arn must equal the supplied s3vectors_kms_key_arn - this module sets it explicitly rather than relying on the index's own inheritance from the bucket (see README)"
  }
}

run "multiple_kbs_independent_keys" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/key-a"
      }
      b = {
        kb_name                   = "kb-b"
        role_name                 = "kb-b-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-b"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-b"
        s3vectors_index_name      = "index-b"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/key-b"
      }
    }
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/key-a"
    error_message = "KB a's vector bucket must use key-a"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["b"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/key-b"
    error_message = "KB b's vector bucket must use key-b, independently of KB a"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["a"].policy).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/key-a"
    error_message = "KB a's S3 Vectors KMS IAM policy must be scoped to key-a only"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["b"].policy).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/key-b"
    error_message = "KB b's S3 Vectors KMS IAM policy must be scoped to key-b only"
  }
}

run "two_kbs_intentionally_sharing_the_same_s3vectors_kms_key" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/shared-key"
      }
      b = {
        kb_name                   = "kb-b"
        role_name                 = "kb-b-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-b"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-b"
        s3vectors_index_name      = "index-b"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/shared-key"
      }
    }
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 2
    error_message = "Two KBs sharing the same key must each still get their own scoped IAM policy - this module does not deduplicate across kbs entries"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["a"].policy).Statement[0].Resource == jsondecode(aws_iam_policy.s3vectors_kms["b"].policy).Statement[0].Resource
    error_message = "Both KBs' policies must resolve to the same key ARN when intentionally configured that way"
  }
}

run "enable_kbs_false_produces_empty_shape" {
  command = plan

  variables {
    enable_kbs = false
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/key-a"
      }
    }
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this) == 0 && length(aws_s3vectors_index.this) == 0
    error_message = "enable_kbs = false must produce zero S3 Vectors resources regardless of s3vectors_kms_key_arn"
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 0
    error_message = "enable_kbs = false must produce zero S3 Vectors KMS IAM policies"
  }
}

run "docs_bucket_kms_key_arn_only_does_not_affect_s3vectors" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/docs-key"
        # s3vectors_kms_key_arn intentionally omitted.
      }
    }
  }

  assert {
    condition     = length(aws_iam_policy.kb_s3_kms) == 1
    error_message = "kms_key_arn (docs bucket) must still produce its own existing IAM policy"
  }

  assert {
    condition     = length(aws_s3vectors_vector_bucket.this["a"].encryption_configuration) == 0 && length(aws_s3vectors_index.this["a"].encryption_configuration) == 0
    error_message = "Setting only the docs-bucket kms_key_arn must not encrypt S3 Vectors - the two are independent security boundaries"
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 0
    error_message = "Setting only the docs-bucket kms_key_arn must not produce an S3 Vectors KMS IAM policy"
  }
}

run "s3vectors_kms_key_arn_only_does_not_affect_docs_bucket" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        s3vectors_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
        # kms_key_arn (docs bucket) intentionally omitted.
      }
    }
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.kb_docs["a"].rule : r.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "AES256"
    error_message = "Setting only s3vectors_kms_key_arn must not change the docs bucket's default SSE-S3 encryption"
  }

  assert {
    condition     = length(aws_iam_policy.kb_s3_kms) == 0
    error_message = "Setting only s3vectors_kms_key_arn must not produce a docs-bucket KMS IAM policy"
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 1
    error_message = "s3vectors_kms_key_arn must still produce its own S3 Vectors KMS IAM policy"
  }
}

run "independent_keys_for_docs_bucket_and_s3vectors" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        kms_key_arn           = "arn:aws:kms:us-east-1:123456789012:key/docs-key"
        s3vectors_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_policy.kb_s3_kms["a"].policy).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/docs-key"
    error_message = "The docs-bucket KMS policy must be scoped to docs-key, not vectors-key"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["a"].policy).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
    error_message = "The S3 Vectors KMS policy must be scoped to vectors-key, not docs-key"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
    error_message = "The vector bucket must use vectors-key, never the docs-bucket key"
  }
}

run "interaction_with_chunking" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 300
            overlap_percentage = 20
          }
        }
      }
    }
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
    error_message = "s3vectors_kms_key_arn must wire correctly alongside chunking"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["a"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "chunking must still be wired when s3vectors_kms_key_arn is also set"
  }
}

run "interaction_with_ingestion_logging" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["a"]
    override_during = plan
    values = {
      id                 = "AAAAAAAAAA"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
      status             = "ACTIVE"
    }
  }

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:my-destination"
        }
      }
    }
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].encryption_configuration[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
    error_message = "s3vectors_kms_key_arn must wire correctly alongside ingestion_logging"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 1
    error_message = "ingestion_logging must still be wired when s3vectors_kms_key_arn is also set"
  }
}

run "interaction_with_expose_ingestion_policy" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["a"]
    override_during = plan
    values = {
      id                 = "AAAAAAAAAA"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
      status             = "ACTIVE"
    }
  }

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"

        expose_ingestion_policy = true
      }
    }
  }

  assert {
    condition     = length(output.ingestion_policy_documents) == 1
    error_message = "expose_ingestion_policy must still produce its output when s3vectors_kms_key_arn is also set"
  }

  assert {
    condition     = !can(regex("kms", jsondecode(output.ingestion_policy_documents["a"]).Statement[0].Action[0]))
    error_message = "A KB with s3vectors_kms_key_arn set must not gain any kms:* action in its ingestion policy - that permission belongs solely to the new, separate s3vectors_kms policy on the Bedrock execution role"
  }
}

run "operational_outputs_regression" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"
        s3vectors_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
      }
    }
  }

  assert {
    condition     = length(output.knowledge_base_ids) == 1 && length(output.knowledge_base_statuses) == 1
    error_message = "PR #14's operational status outputs must be unaffected by s3vectors_kms_key_arn"
  }

  assert {
    condition     = length(output.data_source_ids) == 1 && length(output.data_source_statuses) == 1
    error_message = "PR #14's data source outputs must be unaffected by s3vectors_kms_key_arn"
  }

  assert {
    condition     = length(output.s3vectors_index_arns) == 1
    error_message = "s3vectors_index_arns must be unaffected by s3vectors_kms_key_arn"
  }
}

run "s3vectors_kms_key_arn_empty_string_is_rejected" {
  command = plan

  variables {
    kbs = {
      broken = {
        kb_name                   = "kb-broken"
        role_name                 = "kb-broken-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-broken"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-broken"
        s3vectors_index_name      = "index-broken"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        s3vectors_kms_key_arn = "   "
      }
    }
  }

  expect_failures = [var.kbs]
}

run "iam_policy_is_decrypt_only_and_kept_separate_from_docs_bucket_kms" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name                   = "kb-a"
        role_name                 = "kb-a-role"
        embedding_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket            = "bucket-a"
        create_s3vectors          = true
        s3vectors_bucket_name     = "vectors-a"
        s3vectors_index_name      = "index-a"
        s3vectors_dimension       = 1024
        s3vectors_distance_metric = "cosine"

        kms_key_arn           = "arn:aws:kms:us-east-1:123456789012:key/docs-key"
        s3vectors_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/vectors-key"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["a"].policy).Statement[0].Action == ["kms:Decrypt"]
    error_message = "The S3 Vectors KMS policy must grant exactly kms:Decrypt - not kms:GenerateDataKey, kms:Encrypt, or any other action - per AWS's own S3 Vectors encryption documentation, which names only kms:Decrypt as necessary for IAM principals accessing a KMS-encrypted vector bucket/index"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.s3vectors_kms["a"].policy).Statement[0].Effect == "Allow"
    error_message = "The S3 Vectors KMS policy statement must be Allow"
  }

  assert {
    condition     = aws_iam_policy.s3vectors_kms["a"].name != aws_iam_policy.kb_s3_kms["a"].name
    error_message = "The S3 Vectors KMS policy must be a logically separate IAM policy resource/name from the docs-bucket KMS policy, even when both are present on the same KB"
  }
}

run "v0_3_0_style_configuration_remains_valid" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        # No field introduced by PR #18 is set anywhere in this configuration.
      }
    }
  }

  assert {
    condition     = length(aws_iam_policy.s3vectors_kms) == 0
    error_message = "A v0.3.0-style configuration (s3vectors_kms_key_arn never referenced) must plan with zero S3 Vectors KMS IAM policies"
  }

  assert {
    condition     = length(output.knowledge_base_ids) == 1
    error_message = "A v0.3.0-style configuration must still plan successfully end-to-end"
  }
}
