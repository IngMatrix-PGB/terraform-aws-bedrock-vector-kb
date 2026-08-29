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

    # Docs bucket encryption: bring your own KMS key. Default (null) keeps
    # the existing SSE-S3 (AES256) behavior unchanged. Granting this
    # module's IAM policy kms:Decrypt/kms:GenerateDataKey is not, by
    # itself, sufficient - the key's own key policy must also allow the
    # Bedrock execution role (this module does not manage the key or its
    # key policy, since it only accepts an existing key ARN).
    kms_key_arn = optional(string)

    # Docs bucket access logging: bring your own existing logging-destination
    # bucket. Default (null) leaves logging disabled, unchanged from before.
    # This module does not create or configure the destination bucket -
    # it must already be set up to accept S3 access log delivery.
    logging_target_bucket = optional(string)
    logging_target_prefix = optional(string, "")

    # Docs bucket lifecycle: noncurrent object versions are kept forever
    # unless this is set. null (default) = no automatic deletion of old
    # versions, unchanged from before. When set, noncurrent versions older
    # than this many days are expired. This is destructive retention
    # behavior (it permanently deletes old version content, even though it
    # never touches the current/live version) and is therefore
    # consumer-opt-in only, never a default.
    noncurrent_version_expiration_days = optional(number)
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

  validation {
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.kms_key_arn, null) == null || trimspace(v.kms_key_arn) != ""
      )
    ])
    error_message = "kms_key_arn, when provided, must not be empty or whitespace-only."
  }

  validation {
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.logging_target_bucket, null) == null || trimspace(v.logging_target_bucket) != ""
      )
    ])
    error_message = "logging_target_bucket, when provided, must not be empty or whitespace-only."
  }

  validation {
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.noncurrent_version_expiration_days, null) == null || v.noncurrent_version_expiration_days > 0
      )
    ])
    error_message = "noncurrent_version_expiration_days, when provided, must be a positive number of days."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
