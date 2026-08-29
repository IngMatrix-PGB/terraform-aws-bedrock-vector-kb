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

    # Chunking strategy for this data source's ingestion. null (default,
    # omitted) sends no vector_ingestion_configuration at all, so AWS
    # applies its own default chunking behavior unchanged from v0.1.0.
    # Exactly the block matching `strategy` may be set (enforced below):
    #   FIXED_SIZE   -> fixed_size
    #   HIERARCHICAL -> hierarchical
    #   SEMANTIC     -> semantic
    #   NONE         -> none of the three
    chunking = optional(object({
      strategy = string

      fixed_size = optional(object({
        max_tokens         = number
        overlap_percentage = number
      }))

      hierarchical = optional(object({
        level_configurations = list(object({
          max_tokens = number
        }))
        overlap_tokens = number
      }))

      semantic = optional(object({
        max_tokens                      = number
        buffer_size                     = number
        breakpoint_percentile_threshold = number
      }))
    }), null)

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

  validation { # chunking.strategy, when set, must be a supported value
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.chunking, null) == null ||
        contains(["FIXED_SIZE", "HIERARCHICAL", "SEMANTIC", "NONE"], v.chunking.strategy)
      )
    ])
    error_message = "kbs[*].chunking.strategy, when set, must be one of: FIXED_SIZE, HIERARCHICAL, SEMANTIC, NONE."
  }

  validation { # exactly the config block matching chunking.strategy may be set
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.chunking, null) == null ||
        (
          (v.chunking.strategy == "FIXED_SIZE") == (try(v.chunking.fixed_size, null) != null) &&
          (v.chunking.strategy == "HIERARCHICAL") == (try(v.chunking.hierarchical, null) != null) &&
          (v.chunking.strategy == "SEMANTIC") == (try(v.chunking.semantic, null) != null)
        )
      )
    ])
    error_message = "kbs[*].chunking: exactly one of fixed_size/hierarchical/semantic may be set, and it must match chunking.strategy (FIXED_SIZE with fixed_size, HIERARCHICAL with hierarchical, SEMANTIC with semantic); NONE must leave all three unset."
  }

  validation { # fixed_size ranges, independent of strategy so the message is always specific
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.chunking.fixed_size, null) == null ||
        (
          try(v.chunking.fixed_size.max_tokens >= 1 && v.chunking.fixed_size.max_tokens <= 8192, false) &&
          try(v.chunking.fixed_size.overlap_percentage >= 1 && v.chunking.fixed_size.overlap_percentage <= 99, false)
        )
      )
    ])
    error_message = "kbs[*].chunking.fixed_size, when set: max_tokens must be between 1 and 8192, and overlap_percentage must be between 1 and 99."
  }

  validation { # semantic ranges
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.chunking.semantic, null) == null ||
        (
          try(v.chunking.semantic.max_tokens >= 1 && v.chunking.semantic.max_tokens <= 8192, false) &&
          try(v.chunking.semantic.buffer_size >= 0 && v.chunking.semantic.buffer_size <= 1, false) &&
          try(v.chunking.semantic.breakpoint_percentile_threshold >= 50 && v.chunking.semantic.breakpoint_percentile_threshold <= 99, false)
        )
      )
    ])
    error_message = "kbs[*].chunking.semantic, when set: max_tokens must be between 1 and 8192, buffer_size must be between 0 and 1, and breakpoint_percentile_threshold must be between 50 and 99."
  }

  validation { # hierarchical shape: exactly 2 levels, positive tokens
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.chunking.hierarchical, null) == null ||
        (
          try(length(v.chunking.hierarchical.level_configurations) == 2, false) &&
          try(v.chunking.hierarchical.overlap_tokens >= 1, false) &&
          try(alltrue([for lvl in v.chunking.hierarchical.level_configurations : lvl.max_tokens >= 1]), false)
        )
      )
    ])
    error_message = "kbs[*].chunking.hierarchical, when set: level_configurations must contain exactly 2 entries (each with a positive max_tokens), and overlap_tokens must be >= 1. AWS does not document an ordering requirement between the 2 levels; by convention, list level 1 (broader/parent chunks) before level 2 (narrower/child chunks), but this is not enforced here."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
