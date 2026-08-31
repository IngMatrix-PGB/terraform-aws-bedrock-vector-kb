# Regression coverage for PR #12.1: knowledge_base_arns used to reference
# awscc_bedrock_knowledge_base.this[k].arn, an attribute that does not exist
# on that resource (the real attribute is knowledge_base_arn), so every
# entry silently evaluated to null via try(). This file proves both the
# fixed behavior and that the sibling outputs it did not touch
# (knowledge_base_ids, ingestion_policy_documents) are unaffected.
#
# knowledge_base_arn is a computed attribute, unknown at plan time under
# mock_provider unless given a concrete value - override_resource (not
# mock_resource, which would apply one value to every KB instance) lets
# each KB instance get its own distinct mocked ARN, needed to prove
# multiple KBs resolve independently rather than all reading the same
# provider-wide default. id is overridden alongside it because
# awscc_bedrock_data_source.knowledge_base_id validates against
# ^[0-9a-zA-Z]{10}$, and a partial override on one attribute of an instance
# was found (during PR #12) to disable the mock provider's own
# constraint-aware random generation for that instance's other attributes.

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

run "single_kb_knowledge_base_arns_returns_the_real_arn_not_null" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["a"]
    override_during = plan
    values = {
      id                 = "AAAAAAAAAA"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
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
    condition     = output.knowledge_base_arns["a"] != null
    error_message = "REGRESSION: knowledge_base_arns['a'] must not be null - this is exactly the pre-existing bug (referencing the nonexistent .arn attribute) this PR fixes"
  }

  assert {
    condition     = output.knowledge_base_arns["a"] == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "knowledge_base_arns['a'] must equal the KB's real knowledge_base_arn attribute"
  }
}

run "multiple_kbs_each_return_their_own_arn" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["one"]
    override_during = plan
    values = {
      id                 = "ONEONEONE1"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/ONEONEONE1"
    }
  }

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["two"]
    override_during = plan
    values = {
      id                 = "TWOTWOTWO2"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/TWOTWOTWO2"
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
    condition     = output.knowledge_base_arns["one"] == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/ONEONEONE1"
    error_message = "kb 'one' must resolve to its own knowledge_base_arn"
  }

  assert {
    condition     = output.knowledge_base_arns["two"] == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/TWOTWOTWO2"
    error_message = "kb 'two' must resolve to its own knowledge_base_arn"
  }

  assert {
    condition     = output.knowledge_base_arns["one"] != output.knowledge_base_arns["two"]
    error_message = "Two different KBs must never end up with identical (cross-wired) ARNs"
  }
}

run "enable_kbs_false_preserves_existing_output_shape" {
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
    condition     = length(output.knowledge_base_arns) == 0
    error_message = "enable_kbs = false must still produce an empty map for knowledge_base_arns (same shape as before this fix), not an error or a null-valued entry"
  }
}

run "knowledge_base_ids_output_remains_unchanged" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["a"]
    override_during = plan
    values = {
      id                 = "AAAAAAAAAA"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
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
    error_message = "knowledge_base_ids must remain unaffected by the knowledge_base_arns fix - it already referenced the correct .id attribute"
  }
}

run "ingestion_policy_documents_output_from_pr12_remains_unchanged" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["a"]
    override_during = plan
    values = {
      id                 = "AAAAAAAAAA"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
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
    error_message = "PR #12's ingestion_policy_documents output must be unaffected by this fix - it already referenced the correct knowledge_base_arn attribute directly"
  }

  assert {
    condition     = jsondecode(output.ingestion_policy_documents["a"]).Statement[0].Resource == output.knowledge_base_arns["a"]
    error_message = "Now that both outputs reference the same real attribute, they must agree on the same KB's ARN"
  }
}
