# force_destroy: off by default (destroy fails on a non-empty bucket, AWS's
# own protection), and when opted in it applies to both the documents
# bucket and the module-created S3 Vectors bucket.

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

  mock_resource "aws_s3vectors_index" {
    defaults = {
      index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/mock-vector-bucket/index/mock-vector-index"
    }
  }
}

mock_provider "awscc" {
  override_during = plan
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

      create_s3vectors      = true
      s3vectors_bucket_name = "vectors-a"
      s3vectors_index_name  = "index-a"
    }
  }
}

run "force_destroy_is_off_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.kb_docs["a"].force_destroy == false
    error_message = "The documents bucket must not be force-destroyable unless the caller opts in"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].force_destroy == false
    error_message = "The S3 Vectors bucket must not be force-destroyable unless the caller opts in"
  }
}

run "force_destroy_applies_to_both_buckets_when_set" {
  command = plan

  variables {
    kbs = {
      a = {
        kb_name             = "kb-a"
        role_name           = "kb-a-role"
        embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        content_bucket      = "bucket-a"

        create_s3vectors      = true
        s3vectors_bucket_name = "vectors-a"
        s3vectors_index_name  = "index-a"

        force_destroy = true
      }
    }
  }

  assert {
    condition     = aws_s3_bucket.kb_docs["a"].force_destroy == true
    error_message = "force_destroy = true must reach the documents bucket"
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this["a"].force_destroy == true
    error_message = "force_destroy = true must reach the S3 Vectors bucket"
  }
}
