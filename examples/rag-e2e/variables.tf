variable "region" {
  description = "AWS region. Must support Bedrock Knowledge Bases, S3 Vectors and the chosen models."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource in this example."
  type        = string
  default     = "rag-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 2-21 characters: lowercase letters, digits and hyphens (it is used in S3 bucket names)."
  }
}

variable "embedding_model_id" {
  description = "Bedrock embedding model for the Knowledge Base."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimension" {
  description = "Vector dimension; must be one the embedding model supports."
  type        = number
  default     = 1024
}

variable "generation_inference_profile_id" {
  description = "Cross-region inference profile used to generate answers. Amazon Nova Lite is cheap and needs no use-case form."
  type        = string
  default     = "us.amazon.nova-lite-v1:0"
}

variable "number_of_results" {
  description = "Chunks retrieved from the vector index per question."
  type        = number
  default     = 5

  validation {
    condition     = var.number_of_results >= 1 && var.number_of_results <= 20
    error_message = "number_of_results must be between 1 and 20."
  }
}

variable "guardrail_id" {
  description = "Optional Bedrock Guardrail ID applied to generated answers. null = no guardrail."
  type        = string
  default     = null
}

variable "guardrail_version" {
  description = "Guardrail version used when guardrail_id is set."
  type        = string
  default     = "DRAFT"
}

variable "lambda_reserved_concurrency" {
  description = "Hard cap on concurrent query executions - bounds Bedrock spend if the URL is called in a loop."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the query function."
  type        = number
  default     = 30
}

