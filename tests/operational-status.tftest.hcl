# Coverage for PR #14 (operational status outputs): knowledge_base_statuses,
# data_source_statuses, and data_source_ids, all pure computed-attribute
# passthroughs (no new locals, no new resources, no new IAM). status,
# data_source_status, and data_source_id are all computed attributes -
# unknown at plan time under mock_provider unless given a concrete value via
# override_resource (mock_resource would apply the same value to every KB
# instance, which would defeat the "independently keyed" tests below -
# override_resource lets each KB instance get its own distinct mocked
# value, the same technique already used in tests/ingestion-policy.tftest.hcl
# and tests/outputs.tftest.hcl).

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

run "single_kb_knowledge_base_statuses" {
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
      }
    }
  }

  assert {
    condition     = output.knowledge_base_statuses["a"] == "ACTIVE"
    error_message = "knowledge_base_statuses['a'] must equal the mocked KB status"
  }
}

run "single_kb_data_source_statuses" {
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
      }
    }
  }

  assert {
    condition     = output.data_source_statuses["a"] == "AVAILABLE"
    error_message = "data_source_statuses['a'] must equal the mocked data source status"
  }
}

run "single_kb_data_source_ids" {
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
      }
    }
  }

  assert {
    condition     = output.data_source_ids["a"] == "DSAAAAAAAA"
    error_message = "data_source_ids['a'] must equal the mocked data source ID"
  }
}

run "multiple_kbs_statuses_independently_keyed" {
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
      status             = "CREATING"
    }
  }

  override_resource {
    target          = awscc_bedrock_data_source.s3["one"]
    override_during = plan
    values = {
      data_source_id     = "DSONE00001"
      data_source_status = "AVAILABLE"
    }
  }

  override_resource {
    target          = awscc_bedrock_data_source.s3["two"]
    override_during = plan
    values = {
      data_source_id     = "DSTWO00002"
      data_source_status = "CREATING"
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
      }

      two = {
        kb_name             = "kb-two"
        role_name           = "kb-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-two"
        s3vectors_dimension = 1024

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
      }
    }
  }

  assert {
    condition     = output.knowledge_base_statuses["one"] == "ACTIVE"
    error_message = "kb 'one' status must resolve to its own mocked value"
  }

  assert {
    condition     = output.knowledge_base_statuses["two"] == "CREATING"
    error_message = "kb 'two' status must resolve to its own mocked value"
  }

  assert {
    condition     = output.knowledge_base_statuses["one"] != output.knowledge_base_statuses["two"]
    error_message = "Two different KBs must never end up with identical (cross-wired) statuses"
  }
}

run "multiple_kbs_data_source_statuses_and_ids_independently_keyed" {
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

  override_resource {
    target          = awscc_bedrock_data_source.s3["one"]
    override_during = plan
    values = {
      data_source_id     = "DSONE00001"
      data_source_status = "AVAILABLE"
    }
  }

  override_resource {
    target          = awscc_bedrock_data_source.s3["two"]
    override_during = plan
    values = {
      data_source_id     = "DSTWO00002"
      data_source_status = "CREATING"
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
      }

      two = {
        kb_name             = "kb-two"
        role_name           = "kb-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-two"
        s3vectors_dimension = 1024

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
      }
    }
  }

  assert {
    condition     = output.data_source_ids["one"] == "DSONE00001"
    error_message = "kb 'one' data source ID must resolve to its own mocked value"
  }

  assert {
    condition     = output.data_source_ids["two"] == "DSTWO00002"
    error_message = "kb 'two' data source ID must resolve to its own mocked value"
  }

  assert {
    condition     = output.data_source_statuses["one"] == "AVAILABLE"
    error_message = "kb 'one' data source status must resolve to its own mocked value"
  }

  assert {
    condition     = output.data_source_statuses["two"] == "CREATING"
    error_message = "kb 'two' data source status must resolve to its own mocked value"
  }

  assert {
    condition     = output.data_source_ids["one"] != output.data_source_ids["two"]
    error_message = "Two different KBs must never end up with identical (cross-wired) data source IDs"
  }
}

run "enable_kbs_false_preserves_empty_map_shape_for_all_three_new_outputs" {
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
      }
    }
  }

  assert {
    condition     = length(output.knowledge_base_statuses) == 0
    error_message = "enable_kbs = false must produce an empty map for knowledge_base_statuses, not an error or a null-valued entry"
  }

  assert {
    condition     = length(output.data_source_statuses) == 0
    error_message = "enable_kbs = false must produce an empty map for data_source_statuses"
  }

  assert {
    condition     = length(output.data_source_ids) == 0
    error_message = "enable_kbs = false must produce an empty map for data_source_ids"
  }
}

run "existing_knowledge_base_ids_output_remains_unchanged" {
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
      }
    }
  }

  assert {
    condition     = output.knowledge_base_ids["a"] == "AAAAAAAAAA"
    error_message = "PR #14 must not change knowledge_base_ids' existing behavior"
  }
}

run "existing_knowledge_base_arns_output_remains_unchanged" {
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
      }
    }
  }

  assert {
    condition     = output.knowledge_base_arns["a"] == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "PR #14 must not change knowledge_base_arns' existing (PR #12.1-fixed) behavior"
  }
}

run "existing_ingestion_policy_documents_output_remains_unchanged" {
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

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        expose_ingestion_policy = true
      }
    }
  }

  assert {
    condition     = jsondecode(output.ingestion_policy_documents["a"]).Statement[0].Resource == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "PR #14 must not change PR #12's ingestion_policy_documents behavior"
  }

  assert {
    condition     = output.knowledge_base_statuses["a"] == "ACTIVE"
    error_message = "The new status output must also work correctly on a KB that also has expose_ingestion_policy set"
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
    condition     = output.data_source_statuses["a"] == "AVAILABLE"
    error_message = "Status/ID outputs must work correctly alongside PR #10's chunking configuration"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["a"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "PR #10's chunking wiring must be unaffected by PR #14's status/ID outputs"
  }
}

run "interaction_with_model_dimension_validation" {
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
        s3vectors_dimension = 1024
      }
    }
  }

  assert {
    condition     = output.knowledge_base_ids["a"] == "AAAAAAAAAA"
    error_message = "Status/ID outputs must work correctly alongside a valid, PR #11-validated model/dimension pair"
  }

  assert {
    condition     = output.data_source_ids["a"] == "DSAAAAAAAA"
    error_message = "data_source_ids must resolve correctly when model/dimension validation also passes"
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

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        expose_ingestion_policy = true
      }
    }
  }

  assert {
    condition     = output.data_source_ids["a"] == "DSAAAAAAAA"
    error_message = "data_source_ids must resolve correctly alongside PR #12's expose_ingestion_policy"
  }

  assert {
    condition     = contains(keys(local.ingestion_policy_documents), "a")
    error_message = "expose_ingestion_policy must still produce a policy document when the new status/ID outputs are also present"
  }
}
