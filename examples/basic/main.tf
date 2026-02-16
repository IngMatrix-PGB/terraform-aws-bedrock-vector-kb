terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.24.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "awscc" {
  region = "us-east-1"
}

module "matrix_vector_nexus" {
  source = "../../modules/matrix-vector-nexus"

  kb_prefix  = "matrix"
  enable_kbs = true

  tags = {
    Project = "matrix-vector-nexus"
    Owner   = "ingeniero-matrix"
  }

  kbs = {
    vector_nexus = {
      kb_name             = "knowledge-base-vector-nexus"
      role_name           = "bedrock-kb-vector-nexus-role"
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"

      content_bucket = "matrix-bedrock-documents"
      content_prefix = "vector-nexus/"

      create_s3vectors          = true
      s3vectors_bucket_name     = "matrix-vector-nexus-store"
      s3vectors_index_name      = "matrix-vector-nexus-index"
      s3vectors_dimension       = 1024
      s3vectors_distance_metric = "cosine"
      s3vectors_data_type       = "float32"
    }

    # Example: use an existing index (no creation)
    # existing_index = {
    #   kb_name             = "knowledge-base-existing-index"
    #   role_name           = "bedrock-kb-existing-index-role"
    #   embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    #   content_bucket      = "matrix-bedrock-documents"
    #   content_prefix      = "existing/"
    #   create_s3vectors    = false
    #   s3vectors_index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/example-bucket/index/example-index"
    # }
  }
}
