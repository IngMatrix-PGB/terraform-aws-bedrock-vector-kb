# Coverage for PR #21: the Bedrock Data Source name this module always
# derives as "${kb_name}-docs" (awscc_bedrock_data_source.s3.name in
# main.tf) must remain a valid AWS::Bedrock::DataSource name
# (^([0-9a-zA-Z][_-]?){1,100}$ per the CloudFormation resource schema -
# the identical pattern AWS::Bedrock::KnowledgeBase.Name itself uses, with
# no independent minLength/maxLength anywhere in that schema).
#
# This applies to every enabled kbs entry unconditionally (unlike the
# ingestion_logging-derived delivery-source name, which only applies to
# opt-in entries), so it is covered here rather than folded into any
# single feature's test file.
#
# IMPORTANT: this pattern is a REPETITION-count bound (at most 100 "1
# alphanumeric char + 1 optional separator" units), not a raw
# character-count bound. There is no single fixed raw-length threshold
# that is correct for every kb_name composition - a kb_name using its own
# internal separators can validly exceed what a separator-free kb_name of
# the same raw length could reach, since each separator lets 2 raw
# characters share one repetition. An earlier version of this validation
# used a flat length(...) <= 100 check; that was proven incorrect (it
# rejected valid, AWS-acceptable configurations, confirmed empirically -
# see the boundary test below) and was replaced with a direct match
# against AWS's own exact pattern.
#
# Two independent ways the derived name can be invalid even when kb_name
# is itself a perfectly valid Knowledge Base name:
#   - repetition-count overflow: a separator-free kb_name of 97+
#     characters requires more repetitions than the pattern allows once
#     "-docs" is appended (verified empirically: 96 characters still
#     passes - the derived name's leading "-docs" hyphen absorbs into
#     kb_name's own final character as its optional separator, costing no
#     extra repetition - while 97 characters does not).
#   - charset: a kb_name ending in "-" or "_" (explicitly permitted by
#     the pattern) produces a double-separator sequence once the literal
#     "-docs" suffix (itself starting with "-") is appended - e.g.
#     "my-kb-" + "-docs" = "my-kb--docs", which no valid decomposition of
#     this pattern can match, at any length.
#
# An ordinary kb_name passing is already covered by every other test file
# in this suite (all 109 pre-existing tests use normal kb_name values and
# would fail if this validation regressed them) - not duplicated here.

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
}

mock_provider "awscc" {
  override_during = plan
}

variables {
  enable_kbs = true
  tags       = {}
}

run "derived_data_source_name_for_a_separator_free_96_character_kb_name_passes" {
  command = plan

  variables {
    kbs = {
      a = {
        # 96 separator-free 'a' characters + "-docs" = 101 raw characters,
        # but only 100 repetitions (the final 'a' absorbs the "-docs"
        # prefix's leading hyphen as its own optional separator) - this is
        # the true maximum for a separator-free kb_name, one character
        # higher than a naive raw-length-based check would assume.
        kb_name             = join("", [for i in range(96) : "a"])
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_data_source.s3["a"].name) == 101
    error_message = "A 96-character separator-free kb_name must produce a 101-character derived Data Source name, and must be accepted (100 repetitions exactly)"
  }
}

run "derived_data_source_name_for_a_separator_free_97_character_kb_name_is_rejected" {
  command = plan

  variables {
    kbs = {
      a = {
        # 97 separator-free 'a' characters + "-docs" = 102 raw characters,
        # requiring 101 repetitions - one over the pattern's {1,100} bound.
        kb_name             = join("", [for i in range(97) : "a"])
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
      }
    }
  }

  expect_failures = [var.kbs]
}

run "a_longer_kb_name_using_internal_separators_still_passes" {
  command = plan

  variables {
    kbs = {
      a = {
        # 149 raw characters (74 repetitions of "a-" + a trailing "a") -
        # well over the 96/97-character boundary that applies to a
        # separator-free kb_name, and still valid, because each internal
        # separator lets 2 raw characters share a single repetition. This
        # proves no single fixed raw-length threshold is correct for
        # every kb_name composition - only an exact pattern match is.
        kb_name             = "${join("", [for i in range(74) : "a-"])}a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
      }
    }
  }

  assert {
    condition     = length(awscc_bedrock_data_source.s3["a"].name) == 154
    error_message = "A 149-character kb_name using internal separators, plus \"-docs\", must produce a 154-character derived name and must be accepted"
  }
}

run "kb_name_ending_in_hyphen_is_rejected" {
  command = plan

  variables {
    kbs = {
      a = {
        # Valid per the Knowledge Base's own name pattern (a trailing
        # separator is explicitly permitted), but produces a double
        # hyphen ("my-kb--docs") once this module's "-docs" suffix is
        # appended.
        kb_name             = "my-kb-"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
      }
    }
  }

  expect_failures = [var.kbs]
}

run "kb_name_ending_in_underscore_is_rejected" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name             = "my_kb_"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors    = false
        s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/one/index/one"
      }
    }
  }

  expect_failures = [var.kbs]
}
