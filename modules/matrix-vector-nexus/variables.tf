variable "kb_prefix" {
  description = "Short prefix used for naming/tagging."
  type        = string
  default     = "matrix"
}

variable "account_id" {
  description = "AWS account id (used only for tagging/metadata in some orgs)."
  type        = string
  default     = ""
}

variable "enable_kbs" {
  description = "If false, nothing is created."
  type        = bool
  default     = true
}

variable "kbs" {
  description = "Knowledge Bases definition map."
  type = map(object({
    kb_name             = string
    role_name           = string
    kb_description      = optional(string)
    embedding_model_arn = string

    # Docs source
    content_bucket = string
    content_prefix = optional(string, "")

    # S3 Vectors: either create it, or provide an existing index ARN.
    create_s3vectors          = optional(bool, false)
    s3vectors_bucket_name     = optional(string)
    s3vectors_index_name      = optional(string)
    s3vectors_dimension       = optional(number, 1024)
    s3vectors_distance_metric = optional(string, "cosine") # cosine|euclidean
    s3vectors_data_type       = optional(string, "float32") # currently float32
    s3vectors_index_arn       = optional(string) # used when create_s3vectors=false

    # Optional
    enable_bedrock_data_automation = optional(bool, false)
  }))
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
