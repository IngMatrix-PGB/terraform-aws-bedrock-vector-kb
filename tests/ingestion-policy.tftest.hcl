# Coverage for PR #12 (ingestion boundary + optional IAM permissions): the
# optional kbs[*].expose_ingestion_policy field and the
# local.ingestion_policy_documents it feeds, exposed via the
# ingestion_policy_documents output. This module never creates or attaches
# any IAM resource from this document - it is a pure jsonencode() computation
# (no data source, no resource), so it needs no special mock_data handling.
# It DOES reference awscc_bedrock_knowledge_base.this[k].knowledge_base_arn,
# a computed attribute that is unknown at plan time under mock_provider
# unless given a concrete value via override_resource (mock_resource would
# apply the same value to every KB instance, which would defeat the
# "independently scoped" tests below - override_resource lets each KB
# instance get its own distinct mocked ARN).

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

run "default_configuration_produces_no_ingestion_policy" {
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
        # expose_ingestion_policy intentionally omitted (defaults to false).
      }
    }
  }

  assert {
    condition     = length(local.ingestion_policy_documents) == 0
    error_message = "Omitting expose_ingestion_policy must produce no ingestion policy document at all - preserving existing behavior by default"
  }

  assert {
    condition     = length(output.ingestion_policy_documents) == 0
    error_message = "The ingestion_policy_documents output must be empty when nothing opts in"
  }
}

run "opt_in_produces_a_policy_document_with_exact_actions_and_resource" {
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
    condition     = contains(keys(local.ingestion_policy_documents), "a")
    error_message = "expose_ingestion_policy = true must produce a policy document for that entry"
  }

  assert {
    condition     = toset(jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Action) == toset(["bedrock:StartIngestionJob", "bedrock:GetIngestionJob", "bedrock:ListIngestionJobs"])
    error_message = "The policy must grant exactly StartIngestionJob, GetIngestionJob, and ListIngestionJobs - no more, no fewer"
  }

  assert {
    condition     = jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Effect == "Allow"
    error_message = "The statement must be an Allow effect"
  }

  assert {
    condition     = jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Resource == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/AAAAAAAAAA"
    error_message = "The policy's Resource must be exactly this KB's own ARN (the real resource attribute, not a hand-constructed string)"
  }
}

run "no_wildcard_bedrock_action_or_resource" {
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
    condition     = !contains(jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Action, "bedrock:*")
    error_message = "The policy must never contain a bedrock:* wildcard action"
  }

  assert {
    condition     = !contains(jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Action, "*")
    error_message = "The policy must never contain a bare * action"
  }

  assert {
    condition     = jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Resource != "*"
    error_message = "The policy's Resource must never be a wildcard - AWS supports resource-level scoping to the knowledge-base ARN for all three actions"
  }
}

run "multiple_kbs_get_independently_scoped_policies" {
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

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        expose_ingestion_policy = true
      }

      two = {
        kb_name             = "kb-two"
        role_name           = "kb-two-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
        content_bucket      = "bucket-two"
        s3vectors_dimension = 1024

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
        expose_ingestion_policy = true
      }
    }
  }

  assert {
    condition     = jsondecode(local.ingestion_policy_documents["one"]).Statement[0].Resource == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/ONEONEONE1"
    error_message = "kb 'one' policy must be scoped to its own KB ARN"
  }

  assert {
    condition     = jsondecode(local.ingestion_policy_documents["two"]).Statement[0].Resource == "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/TWOTWOTWO2"
    error_message = "kb 'two' policy must be scoped to its own KB ARN"
  }

  assert {
    condition     = local.ingestion_policy_documents["one"] != local.ingestion_policy_documents["two"]
    error_message = "Two different KBs must never end up with identical (cross-wired) ingestion policy documents"
  }
}

run "one_kb_opted_in_another_not" {
  command = plan

  override_resource {
    target          = awscc_bedrock_knowledge_base.this["opted_in"]
    override_during = plan
    values = {
      id                 = "OPTEDIN001"
      knowledge_base_arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/OPTEDIN001"
    }
  }

  variables {
    enable_kbs = true
    tags       = {}
    kbs = {
      opted_in = {
        kb_name             = "kb-opted-in"
        role_name           = "kb-opted-in-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-opted-in"

        create_s3vectors        = false
        s3vectors_index_arn     = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
        expose_ingestion_policy = true
      }

      not_opted_in = {
        kb_name             = "kb-not-opted-in"
        role_name           = "kb-not-opted-in-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-not-opted-in"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/two/index/two"
      }
    }
  }

  assert {
    condition     = contains(keys(local.ingestion_policy_documents), "opted_in")
    error_message = "The entry with expose_ingestion_policy = true must have a policy document"
  }

  assert {
    condition     = !contains(keys(local.ingestion_policy_documents), "not_opted_in")
    error_message = "The entry without expose_ingestion_policy must have no policy document at all, even though a sibling KB opted in"
  }
}

run "kms_enabled_kb_ingestion_policy_has_no_extra_kms_permissions" {
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
        kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition = alltrue([
      for action in jsondecode(local.ingestion_policy_documents["a"]).Statement[0].Action : !startswith(action, "kms:")
    ])
    error_message = "A KB with kms_key_arn set must not gain any kms:* action in its ingestion policy - that permission belongs solely to the existing, separate kb_s3_kms policy on the Bedrock execution role"
  }
}

run "chunking_interaction_no_behavior_change" {
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
    condition     = contains(keys(local.ingestion_policy_documents), "a")
    error_message = "expose_ingestion_policy must still work when combined with a chunking configuration"
  }

  assert {
    condition     = local.chunking_vector_ingestion_configuration_by_kb["a"].chunking_configuration.chunking_strategy == "FIXED_SIZE"
    error_message = "PR #10's chunking wiring must be unaffected by PR #12's ingestion policy field"
  }
}

run "model_dimension_validation_interaction_no_behavior_change" {
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
        s3vectors_dimension     = 1024
        expose_ingestion_policy = true
      }
    }
  }

  assert {
    condition     = contains(keys(local.ingestion_policy_documents), "a")
    error_message = "expose_ingestion_policy must still work when combined with a valid, validated model/dimension pair"
  }

  assert {
    condition     = length(awscc_bedrock_knowledge_base.this) == 1
    error_message = "PR #11's model/dimension validation must not reject a valid pair just because expose_ingestion_policy is also set"
  }
}
