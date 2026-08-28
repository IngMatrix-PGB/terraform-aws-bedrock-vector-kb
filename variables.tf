# tflint-ignore: terraform_unused_declarations # reserved/no-op input kept intentionally (see PR #1); removal would break existing callers.
variable "kb_prefix" {
  description = "Reserved for future use. Not currently applied to any resource name or tag by this module. Accepted for forward/backward compatibility; safe to omit."
  type        = string
  default     = "matrix"
}

# tflint-ignore: terraform_unused_declarations # reserved/no-op input kept intentionally (see PR #1); removal would break existing callers.
variable "account_id" {
  description = "Reserved for future use. Not currently referenced by any resource, local, or output in this module. Accepted for forward/backward compatibility; safe to omit."
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
    s3vectors_distance_metric = optional(string, "cosine")  # cosine|euclidean
    s3vectors_data_type       = optional(string, "float32") # currently float32
    s3vectors_index_arn       = optional(string)            # used when create_s3vectors=false

    # Reserved: accepted but not yet wired to any resource in this module (no-op today).
    enable_bedrock_data_automation = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.create_s3vectors, false) == true ||
        (v.s3vectors_index_arn != null && trimspace(v.s3vectors_index_arn) != "")
      )
    ])
    error_message = "Each kbs entry with create_s3vectors = false must supply a non-empty s3vectors_index_arn (it was null, omitted, or blank for at least one entry)."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
