# Coverage for PR #11 (embedding model / vector dimension compatibility):
# the kbs[*] validation that checks s3vectors_dimension against
# local.known_embedding_model_dimensions for models this module recognizes,
# passes unknown/future models through automatically, and can be bypassed
# per-entry via skip_dimension_validation. All runs use create_s3vectors =
# false with a pre-existing index ARN to keep mocking minimal, matching the
# existing test suite's style.

mock_provider "aws" {
  override_during = plan

  # Required so aws_iam_role.assume_role_policy (reached once enabled_kbs is
  # non-empty) gets valid JSON instead of a random mocked string - see
  # create-vector-index.tftest.hcl for the full explanation.
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

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

mock_provider "awscc" {
  override_during = plan
}

run "titan_g1_valid_1536" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v1"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1536
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Titan G1 (amazon.titan-embed-text-v1) with its only valid dimension (1536) must pass"
  }
}

run "titan_g1_invalid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v1"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  expect_failures = [var.kbs]
}

run "titan_v2_valid_256" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 256
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Titan V2 with dimension 256 (one of its valid configurable dimensions) must pass"
  }
}

run "titan_v2_valid_512" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 512
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Titan V2 with dimension 512 (one of its valid configurable dimensions) must pass"
  }
}

run "titan_v2_valid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Titan V2 with dimension 1024 (one of its valid configurable dimensions) must pass"
  }
}

run "titan_v2_invalid_1536" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1536
      }
    }
  }

  expect_failures = [var.kbs]
}

run "cohere_english_valid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-english-v3"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Cohere Embed English with its only valid dimension (1024) must pass"
  }
}

run "cohere_english_invalid_512" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-english-v3"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 512
      }
    }
  }

  expect_failures = [var.kbs]
}

run "cohere_multilingual_valid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Cohere Embed Multilingual with its only valid dimension (1024) must pass"
  }
}

run "titan_multimodal_valid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-image-v1"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Titan Multimodal Embeddings G1 with its KB-supported dimension (1024) must pass"
  }
}

run "nova_multimodal_valid_1024" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "Nova Multimodal Embeddings with its KB-supported dimension (1024) must pass"
  }
}

run "unknown_future_model_must_pass" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/some.future-embedding-model-v9:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 99999
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "A model this module does not recognize must pass unconditionally, regardless of dimension - this is what keeps the module usable with new AWS models"
  }
}

run "unrecognized_arn_shape_is_treated_as_unknown_and_must_pass" {
  command = plan

  # A syntactically valid ARN (so it passes the awscc provider's own,
  # independent ARN-format attribute validation on embedding_model_arn -
  # unrelated to this module's compatibility check) that does not match the
  # foundation-model/<id> shape this validation's regex looks for (this one
  # is an inference-profile ARN instead). The model-ID extraction must
  # gracefully fall back to "unknown" rather than crash, and an unknown
  # model always passes regardless of dimension.
  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "An embedding_model_arn that doesn't match Bedrock's foundation-model ARN shape must be treated as unknown (not crash) for this specific compatibility check"
  }
}

run "known_invalid_pair_with_skip_dimension_validation_must_pass" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors          = false
        s3vectors_index_arn       = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension       = 1536 # invalid for Titan V2 per the known map
        skip_dimension_validation = true
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "skip_dimension_validation = true must bypass the compatibility check for a known model, even with an otherwise-invalid dimension"
  }
}

run "v0_1_0_style_configuration_still_passes_unchanged" {
  command = plan

  # Mirrors the exact shape of a v0.1.0 kbs entry (no chunking, no
  # skip_dimension_validation - both introduced after v0.1.0), using the
  # same model/dimension pair as the pre-existing test suite
  # (amazon.titan-embed-text-v2:0 + 1024), which is a known-valid pair.
  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      legacy = {
        kb_name             = "kb-legacy"
        role_name           = "kb-legacy-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "matrix-bedrock-documents"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "A v0.1.0-style kbs entry (default s3vectors_dimension = 1024, no chunking, no skip_dimension_validation) must still pass unchanged"
  }
}

run "multiple_kbs_validated_independently" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      valid_one = {
        kb_name             = "kb-valid-one"
        role_name           = "kb-valid-one-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-valid-one"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }

      valid_two = {
        kb_name             = "kb-valid-two"
        role_name           = "kb-valid-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-valid-two"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 2
    error_message = "Both independently-valid kbs entries must be accepted in the same apply"
  }
}

run "one_invalid_pair_among_multiple_kbs_still_fails" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      valid = {
        kb_name             = "kb-valid"
        role_name           = "kb-valid-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-valid"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024
      }

      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-english-v3"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
        s3vectors_dimension = 999 # invalid for Cohere Embed English
      }
    }
  }

  expect_failures = [var.kbs]
}

run "pr10_interaction_valid_chunking_and_valid_model_dimension_together" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension = 1024

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 512
            overlap_percentage = 20
          }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "A valid PR #10 chunking configuration combined with a valid PR #11 model/dimension pair must both pass together"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["a"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "Chunking wiring introduced in PR #10 must be unaffected by the model/dimension validation introduced in PR #11"
  }
}
