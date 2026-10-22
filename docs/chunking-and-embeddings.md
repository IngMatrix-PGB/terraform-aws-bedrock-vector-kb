# Chunking and Embedding Models

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## Chunking

`kbs[*].chunking` (optional, default `null`) configures how Bedrock splits
documents into chunks before embedding them. Supported strategies, per the
`awscc_bedrock_data_source` provider schema:

| Strategy | Sub-block | Required fields | Ranges |
|---|---|---|---|
| `FIXED_SIZE` | `fixed_size` | `max_tokens`, `overlap_percentage` | `max_tokens` 1-8192, `overlap_percentage` 1-99 |
| `HIERARCHICAL` | `hierarchical` | `level_configurations` (exactly 2 entries, each `{ max_tokens }`), `overlap_tokens` | `overlap_tokens` >= 1, each level's `max_tokens` >= 1 |
| `SEMANTIC` | `semantic` | `max_tokens`, `buffer_size`, `breakpoint_percentile_threshold` | `max_tokens` 1-8192, `buffer_size` 0-1, `breakpoint_percentile_threshold` 50-99 |
| `NONE` | (none) | - | - |

Exactly the sub-block matching `strategy` may be set; all others must be
omitted. This exclusivity and the ranges above are enforced by this
module's own `variable "kbs"` validation - the AWS API and the
`awscc`/CloudFormation schemas only document these constraints in prose and
accept invalid combinations until `apply` time, where they surface as an
opaque `ValidationException`. Failing at `terraform plan` with a clear
message is strictly better.

For `HIERARCHICAL`, AWS requires exactly 2 `level_configurations` but does
not document an ordering requirement between them; by convention, list the
broader/parent level first and the narrower/child level second, but this
module does not enforce that order.

Omitting `chunking` entirely (the default) sends no
`vector_ingestion_configuration` argument to `awscc_bedrock_data_source`, so
AWS applies its own default chunking behavior (~300 tokens per chunk,
respecting sentence boundaries) - unchanged from this module's behavior
before this field existed.

**Replacement semantics:** per the `AWS::Bedrock::DataSource` CloudFormation
resource schema, `ChunkingConfiguration` is a `createOnlyProperty`. Changing
`chunking` on an existing `kbs` entry - including adding it where it was
previously omitted, or removing it - forces `awscc` to **replace** the
underlying data source resource, not update it in place. Replacing the data
source does **not** automatically re-run ingestion: any documents already
ingested under the old data source are not retained or re-ingested
automatically; a new `StartIngestionJob` against the new data source is
required (see [Bedrock / Ingestion Boundary](ingestion.md#bedrock--ingestion-boundary)). This module does not
use `lifecycle { prevent_destroy = true }` to mask this behavior - plan
output will show the replacement plainly before you apply it.

## Embedding Model / Dimension Compatibility

Amazon Bedrock rejects an embedding model / vector dimension pair it
doesn't support only at `apply` time (`CreateKnowledgeBase` /
`UpdateKnowledgeBase` `ValidationException`), with no dry-run available and
no dynamic AWS API this module could query to check compatibility ahead of
time - neither `GetFoundationModel`/`ListFoundationModels` nor Terraform's
own `aws_bedrock_foundation_model` data source expose a "supported output
dimensions" field for any model, at all. This module closes part of that gap
by validating each `kbs` entry's `embedding_model_arn` /
`s3vectors_dimension` pair against a small internal map of models AWS
documents as supported for Knowledge Bases' vector embeddings, at
`terraform plan` time, before anything is created.

This map is a point-in-time snapshot of AWS's own [Knowledge Bases
supported-models documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-supported.html),
current as of this module's PR #11 - **not** an exhaustive or permanent
list. AWS adds embedding models and expands dimension options over time.
Three behaviors follow directly from that:

- A **known** model with a **known-invalid** dimension fails at `plan`
  time with a specific, actionable error (naming the model, the configured
  dimension, and the allowed dimensions) instead of a generic
  `ValidationException` at `apply`.
- An **unknown** model (anything not in this module's map - including any
  model AWS releases after this module was last updated) always **passes**
  validation unconditionally. This module has no way to know whether a
  model it has never heard of is compatible with a given dimension, so it
  does not guess either way; catching that class of mistake is left to AWS
  itself at `apply` time, same as before this validation existed.
- `skip_dimension_validation` (per `kbs` entry, default `false`) is an
  explicit escape hatch for a model this module **does** recognize, for
  when the map is stale - AWS expanded a model's valid dimensions, or
  documentation changed before this module was updated. It does not exist
  to bypass validation for unknown models; those already pass without it.

Models currently in the map:

| Model ID | KB-supported dimensions |
|---|---|
| `amazon.titan-embed-text-v1` | 1536 |
| `amazon.titan-embed-text-v2:0` | 256, 512, 1024 |
| `cohere.embed-english-v3` | 1024 |
| `cohere.embed-multilingual-v3` | 1024 |
| `amazon.titan-embed-image-v1` | 1024 |
| `amazon.nova-2-multimodal-embeddings-v1:0` | 1024 |

Deliberately **not** included, despite appearing adjacent to this list in
AWS's own documentation: Cohere Embed v4 (model ID rendered inconsistently
across AWS's docs, and absent from the Knowledge Bases model/ID table
itself) and a "Cohere Embed v3 (Multimodal)" row that appears in the
Knowledge Bases dimensions table but has no corresponding model card or
model ID anywhere in Bedrock's own model catalog. Both are left out rather
than guessed at.

**A note on `amazon.nova-2-multimodal-embeddings-v1:0` specifically:** its
own Bedrock model card lists "Knowledge base" as an unsupported feature in
its general `bedrock-runtime` capability matrix. That capability matrix
describes using a model as the *generation* model inside a Knowledge
Base's `RetrieveAndGenerate` call, which requires text output - this model
is embedding-only, so it cannot serve that role, unrelated to whether it is
usable as the *embedding* model behind a Knowledge Base's vector index.
The claim of KB compatibility in the table above is scoped specifically to
that narrower, embedding-model question, sourced from Bedrock's dedicated
[Knowledge Bases supported-embedding-models
documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-supported.html#knowledge-base-supported-embeddings),
which does list it. This module does not claim the model is universally
supported across all Bedrock Knowledge Base execution paths - only that it
is documented as an eligible embedding model. It remains in the map on that
basis; it would be removed only if newer official AWS evidence directly
contradicted its eligibility as a KB embedding model, not merely on the
strength of this one capability-matrix flag, which describes a different
capability.
