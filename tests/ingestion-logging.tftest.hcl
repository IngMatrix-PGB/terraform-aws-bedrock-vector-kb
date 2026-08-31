# Coverage for PR #15 (ingestion log delivery, ownership Model B): the
# optional kbs[*].ingestion_logging field and the two resources it creates -
# aws_cloudwatch_log_delivery_source (per KB) and aws_cloudwatch_log_delivery
# (the source-to-destination link). This module never creates the delivery
# DESTINATION itself - every run below supplies an existing destination ARN
# as plain input, exactly as an external consumer would.
#
# These mocked tests prove HCL wiring, dependency graph, map cardinality,
# and regression behavior. They do NOT prove that AWS actually accepts a
# live PutDeliverySource/CreateDelivery call, that APPLICATION_LOGS
# actually arrive at the named destination, or how the aws provider
# behaves on an in-place update vs replacement of an already-applied
# delivery source/destination - none of that is verifiable without live
# AWS credentials, and no live integration test is added in this PR.
#
# resource_arn/delivery_source_name/delivery_destination_arn are set
# directly from other resources' attributes in main.tf, so once those
# upstream attributes are known (via override_resource, the same technique
# used in tests/ingestion-policy.tftest.hcl and tests/outputs.tftest.hcl),
# these input arguments are themselves known at plan time - no additional
# mocking is needed for them. Only the two new resources' own computed
# .arn attribute (used by this PR's two new outputs) needs its own
# override_resource.

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

run "default_configuration_produces_zero_logging_resources" {
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
        # ingestion_logging intentionally omitted (defaults to null).
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 0
    error_message = "Omitting ingestion_logging must produce zero aws_cloudwatch_log_delivery_source resources"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery.ingestion) == 0
    error_message = "Omitting ingestion_logging must produce zero aws_cloudwatch_log_delivery resources"
  }

  assert {
    condition     = length(output.ingestion_log_delivery_source_arns) == 0 && length(output.ingestion_log_delivery_arns) == 0
    error_message = "Both new outputs must be empty maps when nothing opts in"
  }
}

run "single_kb_opt_in_exact_wiring" {
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

  override_resource {
    target          = awscc_bedrock_data_source.s3["a"]
    override_during = plan
    values = {
      data_source_id     = "DSAAAAAAAA"
      data_source_status = "AVAILABLE"
    }
  }

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

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:my-shared-destination"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 1
    error_message = "ingestion_logging = {...} must produce exactly one aws_cloudwatch_log_delivery_source"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery.ingestion) == 1
    error_message = "ingestion_logging = {...} must produce exactly one aws_cloudwatch_log_delivery"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].log_type == "APPLICATION_LOGS"
    error_message = "log_type must be exactly APPLICATION_LOGS"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].name == "kb-a-ingestion-logs"
    error_message = "Delivery source name must be deterministically derived from kb_name"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].resource_arn == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "resource_arn must equal the real knowledge_base_arn attribute, not a hand-constructed string"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["a"].delivery_source_name == aws_cloudwatch_log_delivery_source.ingestion["a"].name
    error_message = "The Delivery's delivery_source_name must reference the actual created DeliverySource for this same KB"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["a"].delivery_destination_arn == "arn:aws:logs:us-east-1:123456789012:delivery-destination:my-shared-destination"
    error_message = "delivery_destination_arn must equal exactly the user-supplied ARN, unmodified"
  }
}

run "multi_kb_mixed_opt_in" {
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

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["b"]
    override_during = plan
    values = {
      id                 = "BBBBBBBBBB"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/BBBBBBBBBB"
      status             = "ACTIVE"
    }
  }

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["c"]
    override_during = plan
    values = {
      id                 = "CCCCCCCCCC"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/CCCCCCCCCC"
      status             = "ACTIVE"
    }
  }

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

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }

      b = {
        kb_name             = "kb-b"
        role_name           = "kb-b-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-b"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
        # ingestion_logging intentionally omitted for kb "b".
      }

      c = {
        kb_name             = "kb-c"
        role_name           = "kb-c-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-c"
        s3vectors_dimension = 1024

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/three/index/three"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-c"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 2
    error_message = "Only the two opted-in KBs (a, c) must get a delivery source"
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_log_delivery_source.ingestion), "a") && contains(keys(aws_cloudwatch_log_delivery_source.ingestion), "c")
    error_message = "Both opted-in KBs must be present by key"
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_log_delivery_source.ingestion), "b")
    error_message = "kb 'b' (not opted in) must have no delivery source at all"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].name != aws_cloudwatch_log_delivery_source.ingestion["c"].name
    error_message = "Different KBs must never end up with identical (cross-wired) delivery source names"
  }
}

run "two_kbs_share_the_same_destination_arn" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["one"]
    override_during = plan
    values = {
      id                 = "ONEONEONE1"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/ONEONEONE1"
      status             = "ACTIVE"
    }
  }

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["two"]
    override_during = plan
    values = {
      id                 = "TWOTWOTWO2"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/TWOTWOTWO2"
      status             = "ACTIVE"
    }
  }

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      one = {
        kb_name             = "kb-one"
        role_name           = "kb-one-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-one"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:shared-destination"
        }
      }

      two = {
        kb_name             = "kb-two"
        role_name           = "kb-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-two"
        s3vectors_dimension = 1024

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:shared-destination"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery.ingestion) == 2
    error_message = "Two KBs intentionally sharing one destination must still produce two independent Delivery resources - no deduplication"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["one"].delivery_destination_arn == aws_cloudwatch_log_delivery.ingestion["two"].delivery_destination_arn
    error_message = "Both Deliveries must reference the identical destination ARN the caller intentionally shared"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["one"].delivery_source_name != aws_cloudwatch_log_delivery.ingestion["two"].delivery_source_name
    error_message = "Even when sharing a destination, each KB must still have its own distinct delivery source"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 2
    error_message = "This module must never create a shared/deduplicated destination-side resource - it never creates a destination resource at all, and each KB still gets its own source"
  }
}

run "two_kbs_distinct_destinations" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["one"]
    override_during = plan
    values = {
      id                 = "ONEONEONE1"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/ONEONEONE1"
      status             = "ACTIVE"
    }
  }

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["two"]
    override_during = plan
    values = {
      id                 = "TWOTWOTWO2"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/TWOTWOTWO2"
      status             = "ACTIVE"
    }
  }

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      one = {
        kb_name             = "kb-one"
        role_name           = "kb-one-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-one"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-one"
        }
      }

      two = {
        kb_name             = "kb-two"
        role_name           = "kb-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-two"
        s3vectors_dimension = 1024

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-two"
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["one"].delivery_destination_arn == "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-one"
    error_message = "kb 'one' must be wired to its own distinct destination"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["two"].delivery_destination_arn == "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-two"
    error_message = "kb 'two' must be wired to its own distinct destination"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.ingestion["one"].delivery_destination_arn != aws_cloudwatch_log_delivery.ingestion["two"].delivery_destination_arn
    error_message = "Distinct destinations must never be cross-wired"
  }
}

run "enable_kbs_false_produces_zero_logging_resources" {
  command = plan

  variables {
    enable_kbs = false
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 0 && length(aws_cloudwatch_log_delivery.ingestion) == 0
    error_message = "enable_kbs = false must produce zero logging resources even though ingestion_logging is set"
  }
}

run "empty_delivery_destination_arn_is_rejected" {
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

        ingestion_logging = {
          delivery_destination_arn = ""
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "whitespace_only_delivery_destination_arn_is_rejected" {
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

        ingestion_logging = {
          delivery_destination_arn = "   "
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "valid_derived_delivery_source_name_passes" {
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

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].name == "kb-a-ingestion-logs"
    error_message = "A normal kb_name must produce a valid, unmodified derived delivery source name"
  }
}

run "derived_delivery_source_name_at_exact_60_character_boundary_passes" {
  command = plan

  # 45 'a' characters + "-ingestion-logs" (15 characters) = exactly 60,
  # PutDeliverySource's documented maximum. This must pass, not fail.
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
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion["a"].name) == 60
    error_message = "A derived name landing exactly at the 60-character maximum must be accepted, not rejected"
  }
}

run "derived_delivery_source_name_over_60_characters_is_rejected" {
  command = plan

  # 46 'a' characters + "-ingestion-logs" (15 characters) = 61, one over
  # PutDeliverySource's documented maximum. This must fail at plan time.
  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "kb_name_with_a_character_invalid_for_delivery_source_naming_is_rejected" {
  command = plan

  # "my.kb" is ALSO independently rejected by awscc_bedrock_knowledge_base's
  # own "name" attribute schema validation
  # (^([0-9a-zA-Z][_-]?){1,100}$ - no dot allowed there either), regardless
  # of ingestion_logging. This test exists to prove this module's own
  # variable validation (not the provider's) is what actually fires here:
  # variable validation runs before any resource is planned, so
  # expect_failures = [var.kbs] confirms THIS validation rejects it first,
  # with a clearer, ingestion_logging-specific message, rather than the
  # generic provider-level error a consumer would otherwise see. It does
  # not prove a real-world gap this validation newly closes - see the
  # module-wide note above local.kbs_with_ingestion_logging (or the PR
  # discussion) on why this charset check is currently unreachable for any
  # kb_name value the KB resource itself would ever accept.
  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "my.kb"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  expect_failures = [var.kbs]
}

run "kb_name_too_long_for_delivery_source_naming_still_passes_without_ingestion_logging" {
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

  # This kb_name (46 'a' characters) is valid for
  # awscc_bedrock_knowledge_base's own "name" pattern (which allows up to
  # 100 characters) and would only be rejected by THIS module's derived-name
  # length check once ingestion_logging is set (see
  # "derived_delivery_source_name_over_60_characters_is_rejected" above).
  # With ingestion_logging omitted, it must still be accepted - proving
  # kb_name is not restricted globally, only when the derived name is
  # actually needed. (A charset-based counter-example is not possible here:
  # awscc_bedrock_knowledge_base's own name pattern
  # (^([0-9a-zA-Z][_-]?){1,100}$) only ever allows characters that already
  # satisfy PutDeliverySource's [\w-]* pattern, so length is the only axis
  # on which a kb_name can be valid for the KB but not for the derived name.)
  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        # ingestion_logging intentionally omitted.
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 0
    error_message = "kb_name is not globally restricted - a length that would be invalid for a derived delivery source name must still be accepted when ingestion_logging is not set"
  }
}

run "interaction_with_chunking" {
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

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }

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
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 1
    error_message = "ingestion_logging must still work alongside PR #10's chunking configuration"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["a"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "PR #10's chunking wiring must be unaffected by ingestion_logging"
  }
}

run "interaction_with_model_dimension_validation_and_expose_ingestion_policy" {
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
    enable_kbs = true
    tags       = {}
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        s3vectors_dimension     = 1024
        expose_ingestion_policy = true

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "A valid, PR #11-validated model/dimension pair must still pass alongside ingestion_logging"
  }

  assert {
    condition     = contains(keys(local.ingestion_policy_documents), "a")
    error_message = "PR #12's expose_ingestion_policy must still work alongside ingestion_logging"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.ingestion) == 1
    error_message = "ingestion_logging must still work alongside expose_ingestion_policy on the same kbs entry"
  }
}

run "interaction_with_operational_status_outputs_and_kms" {
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

  override_resource {
    target          = awscc_bedrock_data_source.s3["a"]
    override_during = plan
    values = {
      data_source_id     = "DSAAAAAAAA"
      data_source_status = "AVAILABLE"
    }
  }

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
        kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = output.knowledge_base_statuses["a"] == "ACTIVE"
    error_message = "PR #14's knowledge_base_statuses must remain unaffected by ingestion_logging"
  }

  assert {
    condition     = output.data_source_statuses["a"] == "AVAILABLE"
    error_message = "PR #14's data_source_statuses must remain unaffected by ingestion_logging"
  }

  assert {
    condition     = output.data_source_ids["a"] == "DSAAAAAAAA"
    error_message = "PR #14's data_source_ids must remain unaffected by ingestion_logging"
  }

  assert {
    condition     = output.knowledge_base_arns["a"] == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "PR #12.1's knowledge_base_arns must remain unaffected by ingestion_logging"
  }

  # aws_cloudwatch_log_delivery_source and aws_cloudwatch_log_delivery have
  # no KMS-related argument in their schema at all (verified directly
  # against `terraform providers schema -json` during discovery) - there is
  # structurally nowhere for a KB's docs-bucket kms_key_arn to leak into.
  # This run instead proves the more meaningful thing: a KB using
  # kms_key_arn still plans correctly, with exactly the same ingestion
  # logging wiring, when ingestion_logging is also set on that same entry.
  assert {
    condition     = aws_cloudwatch_log_delivery_source.ingestion["a"].resource_arn == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "ingestion_logging must wire correctly even when the same kbs entry also sets kms_key_arn"
  }
}

run "new_outputs_expose_exact_computed_arns" {
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

  override_resource {
    target          = aws_cloudwatch_log_delivery_source.ingestion["a"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-source:kb-a-ingestion-logs"
    }
  }

  override_resource {
    target          = aws_cloudwatch_log_delivery.ingestion["a"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery:abcdef1234567890"
    }
  }

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

        ingestion_logging = {
          delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:dest-a"
        }
      }
    }
  }

  assert {
    condition     = output.ingestion_log_delivery_source_arns["a"] == "arn:aws:logs:us-east-1:123456789012:delivery-source:kb-a-ingestion-logs"
    error_message = "ingestion_log_delivery_source_arns must expose the real computed .arn attribute"
  }

  assert {
    condition     = output.ingestion_log_delivery_arns["a"] == "arn:aws:logs:us-east-1:123456789012:delivery:abcdef1234567890"
    error_message = "ingestion_log_delivery_arns must expose the real computed .arn attribute"
  }
}
