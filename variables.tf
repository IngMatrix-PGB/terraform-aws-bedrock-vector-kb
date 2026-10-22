variable "enable_kbs" {
  description = "If false, nothing is created."
  type        = bool
  default     = true
}

# Embedding models AWS documents as supported for Bedrock Knowledge Bases'
# vector embeddings, mapped to their Knowledge-Bases-supported output
# dimensions, per https://docs.aws.amazon.com/bedrock/latest/userguide/
# knowledge-base-supported.html (current as of this module's PR #11).
#
# This map is a point-in-time snapshot, not an exhaustive or permanent list:
# AWS adds embedding models and dimension options over time (observed
# roughly every 4-5 months historically), and this module has no way to
# query that support dynamically - neither the Bedrock API
# (GetFoundationModel/ListFoundationModels) nor the aws_bedrock_foundation_model
# Terraform data source expose a "supported dimensions" field at all. A
# model that is not a key in this map is treated as UNKNOWN and always
# passes the compatibility check below (see the kbs validation) - this
# keeps the module usable with any embedding model AWS releases after this
# map was last updated, at the cost of not catching a bad dimension for
# models this map doesn't yet know about.
#
# Deliberately excluded, despite appearing to be embedding-model options
# with a Knowledge-Bases-published dimension: Cohere Embed v4 (its model ID
# in Bedrock's own KB-embeddings table is inconsistently rendered elsewhere
# in AWS's docs, and it is not listed in the KB embeddings model/ID table
# itself) and "Cohere Embed v3 (Multimodal)" (it appears as a named row in
# the KB dimensions table but has no corresponding entry in Bedrock's model
# catalog or model-ID table under any Cohere model card - its exact
# Knowledge-Bases model ID cannot be confirmed). Both are left out rather
# than guessed at; see docs/chunking-and-embeddings.md "Embedding Model / Dimension
# Compatibility".
locals {
  known_embedding_model_dimensions = {
    "amazon.titan-embed-text-v1"               = [1536]
    "amazon.titan-embed-text-v2:0"             = [256, 512, 1024]
    "cohere.embed-english-v3"                  = [1024]
    "cohere.embed-multilingual-v3"             = [1024]
    "amazon.titan-embed-image-v1"              = [1024]
    "amazon.nova-2-multimodal-embeddings-v1:0" = [1024]
  }
}

variable "kbs" {
  description = "Knowledge Bases definition map."
  type = map(object({
    kb_name             = string
    role_name           = string
    kb_description      = optional(string)
    embedding_model_arn = string

    # Explicit escape hatch for the compatibility check below (see
    # known_embedding_model_dimensions). Only meaningful for a model this
    # module already recognizes: set to true when the maintained map is
    # stale (AWS expanded the model's valid dimensions, or documentation
    # changed before this module was updated) and you have independently
    # confirmed the pair is valid. Unknown/future models never need this -
    # they already pass automatically since the module cannot validate what
    # it doesn't recognize.
    skip_dimension_validation = optional(bool, false)

    # When true, this module computes (but does not create or attach) an
    # IAM policy document (see output "ingestion_policy_documents")
    # granting the minimal permissions an external actor needs to manage
    # ingestion jobs for this KB: bedrock:StartIngestionJob,
    # GetIngestionJob, ListIngestionJobs, scoped to this KB's own ARN. This
    # module never calls StartIngestionJob itself and never attaches this
    # document to any principal - see "Bedrock / Ingestion Boundary" in
    # docs/ingestion.md for why, and for who should use the resulting document.
    expose_ingestion_policy = optional(bool, false)

    # When set, this module creates an AWS Logs vended-log delivery pipe
    # (aws_cloudwatch_log_delivery_source + aws_cloudwatch_log_delivery) for
    # this KB's APPLICATION_LOGS (ingestion/document-status events), sending
    # them to an EXISTING delivery destination the caller already owns. This
    # module never creates the destination (CloudWatch Logs, S3, or Data
    # Firehose) or an aws_cloudwatch_log_delivery_destination resource -
    # only the source and the source-to-destination link. Default null
    # (omitted) creates neither resource. See docs/ingestion.md "Ingestion Log
    # Delivery".
    ingestion_logging = optional(object({
      delivery_destination_arn = string
    }))

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

    # S3 Vectors encryption: bring your own KMS key. Default (null) keeps
    # AWS's own default encryption unchanged. Only applies when
    # create_s3vectors = true - this module does not know the encryption
    # state of an externally-provided s3vectors_index_arn, and cannot
    # configure encryption on a resource it does not create. Applied
    # identically to both the vector bucket and its index (see
    # docs/encryption.md "S3 Vectors Encryption" for why this module sets it on both
    # explicitly rather than relying on the vector index's own encryption
    # inheritance from its bucket). This is a SEPARATE security boundary
    # from the docs bucket's kms_key_arn below - the two may use different
    # keys, and setting this one does not require or imply setting that
    # one. AWS documents S3 Vectors encryption settings as unable to change
    # after the vector bucket/index is created - see "S3 Vectors Encryption"
    # for the resulting replacement/data-loss risk if set on an existing
    # kbs entry.
    s3vectors_kms_key_arn = optional(string)

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

    # Lets `terraform destroy` delete the documents bucket (every object
    # version included) and the module-created S3 Vectors bucket even when
    # they still hold data. false (default) keeps AWS's protection: destroy
    # fails on a non-empty bucket. Meant for demos and ephemeral
    # environments - never set it where the documents or vectors matter.
    force_destroy = optional(bool, false)
  }))

  # This module unconditionally derives the Bedrock Data Source's name as
  # "${kb_name}-docs" (see awscc_bedrock_data_source.s3.name in main.tf) -
  # unlike the ingestion_logging-derived delivery-source name, this applies
  # to every enabled kbs entry, not just an opt-in subset.
  #
  # AWS::Bedrock::DataSource.Name (per the CloudFormation resource schema)
  # has ONLY a pattern constraint - ^([0-9a-zA-Z][_-]?){1,100}$ - with no
  # independent minLength/maxLength anywhere in the schema (confirmed by
  # inspecting the complete property definition, not just the regex).
  # Critically, this is a REPETITION-count bound (at most 100 "1
  # alphanumeric char + 1 optional separator" units), not a raw
  # character-count bound: verified empirically that a 96-character,
  # separator-free kb_name produces a 101-character derived name that
  # STILL matches (the trailing "-docs" hyphen absorbs into kb_name's
  # final character as its optional separator, costing zero extra
  # repetitions), while a 97-character version (102 raw characters) does
  # not. No fixed raw-length threshold is correct for every kb_name
  # composition - a kb_name containing its own internal separators can
  # validly exceed either boundary, since each separator lets 2 raw
  # characters share a single repetition. A prior version of this
  # validation used a flat length(...) <= 100 check; that was proven
  # incorrect (it rejected valid, AWS-acceptable configurations) and has
  # been replaced with a direct match against AWS's own exact pattern,
  # which is the only representation that is neither too strict nor too
  # permissive for every possible kb_name composition.
  #
  # A second, independent, purely charset-driven failure exists
  # regardless of length: kb_name is allowed to END in a "-" or "_" under
  # this exact pattern (a repetition's optional separator is unconstrained
  # on the final repetition). Appending the literal "-docs" suffix (which
  # itself starts with "-") to such a kb_name produces two consecutive
  # separator characters (e.g. kb_name = "my-kb-" -> derived =
  # "my-kb--docs"), which no valid decomposition of this pattern can
  # match, at any length. Verified empirically: "my-kb-" is accepted by
  # this exact regex, but "my-kb--docs" is rejected by it. This case is
  # kept as its own, separate validation (in addition to being covered by
  # the general pattern-match check below) purely for a clearer,
  # more specific error message - it is the single most likely way a
  # valid kb_name breaks this module's derivation in practice.
  #
  # Neither check restricts kb_name's format in general - this module
  # still does not validate kb_name globally, since AWS's own
  # CreateKnowledgeBase API is the authority on kb_name's own validity.
  # Both exist solely because concatenating "-docs" onto kb_name is this
  # module's own derivation, and only THIS module can catch the resulting
  # failure before an opaque CloudFormation error at apply time.
  validation {
    condition = alltrue([
      for k, v in var.kbs : can(regex("^([0-9a-zA-Z][_-]?){1,100}$", "${v.kb_name}-docs"))
    ])
    error_message = "kbs[*].kb_name produces an invalid Bedrock Data Source name once this module appends its literal \"-docs\" suffix (\"$${kb_name}-docs\" must match AWS::Bedrock::DataSource's exact Name pattern ^([0-9a-zA-Z][_-]?){1,100}$ - at most 100 repetitions of one alphanumeric character optionally followed by one hyphen or underscore). kb_name itself may be a perfectly valid Knowledge Base name; this is specific to the derived name this module constructs. Shorten kb_name, or reduce how many separator characters it uses relative to its length, for the affected entry."
  }

  validation {
    condition = alltrue([
      for k, v in var.kbs : !can(regex("[_-]$", v.kb_name))
    ])
    error_message = "kbs[*].kb_name must not end in \"-\" or \"_\" - this module always derives the Bedrock Data Source name by appending the literal \"-docs\" suffix to kb_name, and a kb_name ending in a separator character produces two consecutive separator characters in the derived name (e.g. \"my-kb-\" + \"-docs\" = \"my-kb--docs\"), which AWS::Bedrock::DataSource's Name pattern rejects regardless of length. kb_name itself may otherwise be a perfectly valid Knowledge Base name; only the trailing separator combined with this module's own derivation is the problem."
  }

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
        try(v.s3vectors_kms_key_arn, null) == null || trimspace(v.s3vectors_kms_key_arn) != ""
      )
    ])
    error_message = "s3vectors_kms_key_arn, when provided, must not be empty or whitespace-only."
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

  # Embedding model / vector dimension compatibility.
  #
  # The model ID is extracted from embedding_model_arn inline (not via a
  # separate local) because a variable's own validation block cannot
  # reference any local that itself depends on that same variable - doing
  # so is a genuine dependency cycle in Terraform 1.15.5, confirmed
  # empirically while designing this validation, not merely a historical
  # restriction. local.known_embedding_model_dimensions is safe to
  # reference here because it is a constant, independent of var.kbs.
  #
  # An ARN that doesn't match Bedrock's foundation-model ARN shape
  # (arn:aws:bedrock:<region>::foundation-model/<model-id>) yields model_id
  # = null via try(), which is treated as UNKNOWN below - this validation
  # never crashes on an unfamiliar ARN shape, and any separate ARN-format
  # validation this module may add later stays fully independent of this
  # compatibility check.
  validation {
    condition = alltrue(flatten([
      for k, v in var.kbs : [
        for model_id in [try(regex("^arn:aws:bedrock:[^:]*:[^:]*:foundation-model/(.+)$", v.embedding_model_arn)[0], null)] : (
          try(v.skip_dimension_validation, false) == true ||
          model_id == null ||
          !contains(keys(local.known_embedding_model_dimensions), model_id) ||
          contains(local.known_embedding_model_dimensions[model_id], v.s3vectors_dimension)
        )
      ]
    ]))

    error_message = join(" ", [
      "One or more kbs entries use a known embedding model with an unsupported vector dimension:",
      join("; ", flatten([
        for k, v in var.kbs : [
          for model_id in [try(regex("^arn:aws:bedrock:[^:]*:[^:]*:foundation-model/(.+)$", v.embedding_model_arn)[0], null)] : (
            "kbs[\"${k}\"]: embedding model ${model_id} does not support vector dimension ${v.s3vectors_dimension}. Allowed dimensions: ${join(", ", try(local.known_embedding_model_dimensions[model_id], []))}."
          )
          if !(
            try(v.skip_dimension_validation, false) == true ||
            model_id == null ||
            !contains(keys(local.known_embedding_model_dimensions), model_id) ||
            contains(local.known_embedding_model_dimensions[model_id], v.s3vectors_dimension)
          )
        ]
      ])),
      "Set skip_dimension_validation = true on the specific kbs entry to bypass this check if you have confirmed the model now supports this dimension."
    ])
  }

  validation { # ingestion_logging.delivery_destination_arn, when set, must not be empty/whitespace-only
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.ingestion_logging, null) == null || trimspace(v.ingestion_logging.delivery_destination_arn) != ""
      )
    ])
    error_message = "ingestion_logging.delivery_destination_arn, when set, must not be empty or whitespace-only. This module does not validate the ARN's format or destination type beyond that - AWS is the authority on whether it names a valid delivery destination."
  }

  validation { # the derived delivery source name ("${kb_name}-ingestion-logs") must fit AWS's 60-character limit
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.ingestion_logging, null) == null || length("${v.kb_name}-ingestion-logs") <= 60
      )
    ])
    error_message = "kbs[*].kb_name is too long to derive a delivery source name (\"$${kb_name}-ingestion-logs\" must be at most 60 characters, per PutDeliverySource's name constraint) for an entry with ingestion_logging set. Shorten kb_name for that entry."
  }

  validation { # the derived delivery source name must match PutDeliverySource's [\w-]* charset (word characters and hyphens only)
    # This module does not restrict kb_name's charset globally - kb_name has
    # no format validation elsewhere in this module, and AWS's own
    # CreateKnowledgeBase API is the authority on whether it's a valid KB
    # name. This check exists only because the DERIVED delivery source name
    # has a stricter, distinct charset requirement, and only applies when
    # ingestion_logging is set.
    #
    # In practice, this specific check is unreachable for any kb_name value
    # awscc_bedrock_knowledge_base would ever actually accept:
    # awscc_bedrock_knowledge_base's own "name" attribute already enforces
    # ^([0-9a-zA-Z][_-]?){1,100}$, whose character set (alphanumeric,
    # underscore, hyphen) is always a subset of PutDeliverySource's [\w-]*
    # - there is no string that satisfies the KB's own name pattern but
    # violates this one. It is kept anyway because it fires earlier (during
    # variable validation, before any resource is planned) with a clearer,
    # ingestion_logging-specific message than the generic provider-level
    # schema error a consumer would otherwise see, and as a safeguard
    # against these two independent constraints ever diverging in the
    # future. The 60-character length validation just above this one is
    # the one that is actually reachable in practice - a kb_name can easily
    # be valid for the KB (up to 100 characters) while being too long once
    # "-ingestion-logs" is appended (over DeliverySource's 60-character
    # limit).
    condition = alltrue([
      for k, v in var.kbs : (
        try(v.ingestion_logging, null) == null || can(regex("^[\\w-]*$", "${v.kb_name}-ingestion-logs"))
      )
    ])
    error_message = "kbs[*].kb_name contains a character that is not valid in a derived delivery source name (\"$${kb_name}-ingestion-logs\" must match PutDeliverySource's required pattern [\\w-]* - letters, digits, underscore, and hyphen only) for an entry with ingestion_logging set. This does not restrict kb_name in general - only entries with ingestion_logging set are affected."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
