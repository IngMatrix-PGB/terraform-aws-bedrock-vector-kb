# Coverage for PR #10 (configurable chunking): the optional kbs[*].chunking
# object, its wiring into awscc_bedrock_data_source's
# vector_ingestion_configuration, and the variable validation that enforces
# AWS's documented per-strategy shape/range constraints (which the provider
# and CloudFormation schemas do not enforce themselves - see the discovery
# report). All runs use create_s3vectors = false with a pre-existing index
# ARN, since chunking is independent of the S3 Vectors provisioning mode -
# this keeps mocking minimal, matching the existing test suite's style.

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

run "chunking_omitted_preserves_v0_1_0_default_behavior" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      no_chunking = {
        kb_name             = "kb-no-chunking"
        role_name           = "kb-no-chunking-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-no-chunking"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        # chunking intentionally omitted (evaluates to null).
      }
    }
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["no_chunking"] == null
    error_message = "Omitting chunking must send no vector_ingestion_configuration at all, preserving AWS's own default chunking behavior unchanged from v0.1.0."
  }
}

run "valid_fixed_size_is_wired_correctly" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      fixed = {
        kb_name             = "kb-fixed"
        role_name           = "kb-fixed-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-fixed"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

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
    condition     = local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "chunking_strategy must be wired through as FIXED_SIZE"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.fixed_size_chunking_configuration.max_tokens == 512
    error_message = "fixed_size_chunking_configuration.max_tokens must match the supplied value"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.fixed_size_chunking_configuration.overlap_percentage == 20
    error_message = "fixed_size_chunking_configuration.overlap_percentage must match the supplied value"
  }

  assert {
    condition     = try(local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.hierarchical_chunking_configuration, null) == null
    error_message = "hierarchical_chunking_configuration must be absent when strategy is FIXED_SIZE"
  }

  assert {
    condition     = try(local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.semantic_chunking_configuration, null) == null
    error_message = "semantic_chunking_configuration must be absent when strategy is FIXED_SIZE"
  }
}

run "invalid_fixed_size_max_tokens_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 8193 # out of AWS's documented 1..8192 range
            overlap_percentage = 20
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "invalid_fixed_size_overlap_percentage_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 512
            overlap_percentage = 100 # out of AWS's documented 1..99 range
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "valid_semantic_is_wired_correctly" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      semantic = {
        kb_name             = "kb-semantic"
        role_name           = "kb-semantic-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-semantic"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "SEMANTIC"
          semantic = {
            max_tokens                      = 300
            buffer_size                     = 1
            breakpoint_percentile_threshold = 90
          }
        }
      }
    }
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.chunking_strategy == "SEMANTIC"
    error_message = "chunking_strategy must be wired through as SEMANTIC"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.semantic_chunking_configuration.max_tokens == 300
    error_message = "semantic_chunking_configuration.max_tokens must match the supplied value"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.semantic_chunking_configuration.buffer_size == 1
    error_message = "semantic_chunking_configuration.buffer_size must match the supplied value"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.semantic_chunking_configuration.breakpoint_percentile_threshold == 90
    error_message = "semantic_chunking_configuration.breakpoint_percentile_threshold must match the supplied value"
  }

  assert {
    condition     = try(local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.fixed_size_chunking_configuration, null) == null
    error_message = "fixed_size_chunking_configuration must be absent when strategy is SEMANTIC"
  }
}

run "invalid_semantic_buffer_size_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "SEMANTIC"
          semantic = {
            max_tokens                      = 300
            buffer_size                     = 2 # out of AWS's documented 0..1 range
            breakpoint_percentile_threshold = 90
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "invalid_semantic_breakpoint_percentile_threshold_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "SEMANTIC"
          semantic = {
            max_tokens                      = 300
            buffer_size                     = 1
            breakpoint_percentile_threshold = 40 # out of AWS's documented 50..99 range
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "valid_hierarchical_with_exactly_two_levels_is_wired_correctly" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      hierarchical = {
        kb_name             = "kb-hierarchical"
        role_name           = "kb-hierarchical-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-hierarchical"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "HIERARCHICAL"
          hierarchical = {
            overlap_tokens = 60
            level_configurations = [
              { max_tokens = 1500 },
              { max_tokens = 300 },
            ]
          }
        }
      }
    }
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.chunking_strategy == "HIERARCHICAL"
    error_message = "chunking_strategy must be wired through as HIERARCHICAL"
  }

  assert {
    condition     = length(local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.hierarchical_chunking_configuration.level_configurations) == 2
    error_message = "hierarchical_chunking_configuration.level_configurations must carry through exactly 2 levels"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.hierarchical_chunking_configuration.level_configurations[0].max_tokens == 1500
    error_message = "level_configurations[0].max_tokens must match the supplied value"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.hierarchical_chunking_configuration.level_configurations[1].max_tokens == 300
    error_message = "level_configurations[1].max_tokens must match the supplied value"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.hierarchical_chunking_configuration.overlap_tokens == 60
    error_message = "hierarchical_chunking_configuration.overlap_tokens must match the supplied value"
  }

  assert {
    condition     = try(local.chunking_vector_ingestion_configuration_by_kb["hierarchical"].chunking_configuration.fixed_size_chunking_configuration, null) == null
    error_message = "fixed_size_chunking_configuration must be absent when strategy is HIERARCHICAL"
  }
}

run "invalid_hierarchical_with_one_level_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "HIERARCHICAL"
          hierarchical = {
            overlap_tokens = 60
            level_configurations = [
              { max_tokens = 1500 },
            ]
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "invalid_hierarchical_with_three_levels_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "HIERARCHICAL"
          hierarchical = {
            overlap_tokens = 60
            level_configurations = [
              { max_tokens = 1500 },
              { max_tokens = 500 },
              { max_tokens = 300 },
            ]
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "valid_none_is_wired_correctly" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      none = {
        kb_name             = "kb-none"
        role_name           = "kb-none-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-none"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "NONE"
        }
      }
    }
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["none"].chunking_configuration.chunking_strategy == "NONE"
    error_message = "chunking_strategy must be wired through as NONE"
  }

  assert {
    condition = (
      try(local.chunking_vector_ingestion_configuration_by_kb["none"].chunking_configuration.fixed_size_chunking_configuration, null) == null &&
      try(local.chunking_vector_ingestion_configuration_by_kb["none"].chunking_configuration.hierarchical_chunking_configuration, null) == null &&
      try(local.chunking_vector_ingestion_configuration_by_kb["none"].chunking_configuration.semantic_chunking_configuration, null) == null
    )
    error_message = "NONE must leave all three sub-configurations unset"
  }
}

run "invalid_mixed_configuration_is_rejected" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      broken = {
        kb_name             = "kb-broken"
        role_name           = "kb-broken-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-broken"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 512
            overlap_percentage = 20
          }
          # hierarchical must not be set alongside strategy = FIXED_SIZE.
          hierarchical = {
            overlap_tokens = 60
            level_configurations = [
              { max_tokens = 1500 },
              { max_tokens = 300 },
            ]
          }
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "multiple_kbs_with_different_chunking_strategies_are_independent" {
  command = plan

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      fixed = {
        kb_name             = "kb-fixed"
        role_name           = "kb-fixed-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-fixed"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        chunking = {
          strategy = "FIXED_SIZE"
          fixed_size = {
            max_tokens         = 512
            overlap_percentage = 20
          }
        }
      }

      no_chunking = {
        kb_name             = "kb-no-chunking"
        role_name           = "kb-no-chunking-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-no-chunking"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
        # chunking intentionally omitted.
      }

      semantic = {
        kb_name             = "kb-semantic"
        role_name           = "kb-semantic-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-semantic"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/three/index/three"

        chunking = {
          strategy = "SEMANTIC"
          semantic = {
            max_tokens                      = 300
            buffer_size                     = 1
            breakpoint_percentile_threshold = 90
          }
        }
      }
    }
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["fixed"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "The fixed entry must keep its own FIXED_SIZE configuration"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["no_chunking"] == null
    error_message = "The no_chunking entry must remain entirely unaffected by its siblings' chunking configuration"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["semantic"].chunking_configuration.chunking_strategy == "SEMANTIC"
    error_message = "The semantic entry must keep its own SEMANTIC configuration"
  }
}
