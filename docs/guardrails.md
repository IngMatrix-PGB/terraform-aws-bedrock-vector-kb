# Guardrails Integration

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## Guardrails Integration Boundary

**This module does not create, version, or attach Amazon Bedrock
Guardrails.** This is a deliberate architectural decision, not an
unfinished feature - and not a claim that Terraform is incapable of it.
The `hashicorp/aws` and `hashicorp/awscc` providers both fully support
creating `aws_bedrock_guardrail`/`aws_bedrock_guardrail_version` resources.
This module chooses not to, for reasons specific to what it owns.

**Where Guardrails actually attach.** Verified directly against the
current Bedrock API reference: `CreateKnowledgeBase`, `UpdateKnowledgeBase`,
and `CreateDataSource` expose no guardrail-related field anywhere in their
request or response shape - there is no declarative attachment point on
the Knowledge Base or Data Source resources this module provisions.
Guardrails are instead supplied as runtime configuration to:
- `Retrieve` - accepts a top-level `guardrailConfiguration`
  (`guardrailId`/`guardrailVersion`), but this operation never generates a
  response beyond `retrievalResults` (retrieved chunks), so a guardrail
  here can only meaningfully evaluate the retrieval query itself, not any
  generated content.
- `RetrieveAndGenerate` - the field lives at exactly
  `retrieveAndGenerateConfiguration.knowledgeBaseConfiguration.generationConfiguration.guardrailConfiguration`
  - nested inside the *generation* step, a sibling of `inferenceConfig`
  and `promptTemplate`, never inside `retrievalConfiguration` or
  `orchestrationConfiguration`.
- `CreateAgent` (Bedrock Agents) - accepts its own top-level
  `guardrailConfiguration` (`guardrailIdentifier`/`guardrailVersion`).
  This module creates no Agent resource.

**What a Guardrail actually evaluates.** Per AWS's own Guardrails
documentation: *"it will evaluate the input prompts and the FM
completions against the defined filters."* Concretely, in a RAG flow via
`RetrieveAndGenerate`, that means: (A) **retrieval** - querying the
Knowledge Base for chunks - happens entirely outside guardrail evaluation;
(B) **generation** - the foundation model producing a response from the
retrieved context - is where `guardrailConfiguration` is actually wired;
(C) **guardrail evaluation** itself acts on the assembled input prompt and
the model's completion. AWS explicitly notes that in RAG applications the
"input prompt" **includes retrieved search results by default** unless the
caller uses a separate SDK-only tagging mechanism to exclude them from
evaluation - Guardrails do not treat "content retrieved from a Knowledge
Base" as a distinct, independently-filtered category on their own.
Contextual grounding checks (a distinct Guardrails capability) run
**output only**, checking the model's response against a manually supplied
reference source - AWS states explicitly that this check "will only be
performed on output and not on the prompt." No AWS documentation found
establishes that Guardrails independently filter, authorize, or gate
vectors or documents inside a Knowledge Base.

**Guardrails are not, and must not be described as:** IAM authorization,
S3 bucket security, S3 Vectors encryption, KMS, document ingestion
filtering, or retrieval authorization. Each of those is a separate,
already-documented boundary elsewhere in this README (see [IAM Boundaries](ingestion.md#iam-boundaries), [S3 Vectors Encryption](encryption.md#s3-vectors-encryption), [KMS Boundary](encryption.md#kms-boundary), [Bedrock / Ingestion Boundary](ingestion.md#bedrock--ingestion-boundary)).

**Why this module does not own Guardrail creation.** Knowledge
Base/Data Source resources expose no declarative Guardrail attachment
point; Guardrails are consumed by runtime generation calls or by an Agent
resource, and this module owns neither runtime orchestration nor Agents.
Creating a Guardrail resource here would produce an independent artifact
that nothing this module provisions actually consumes - it would expand
this module's ownership without improving the Knowledge Base resource
graph it exists to manage. This keeps the module's scope to what it states
in [Architecture](../README.md#architecture): Amazon Bedrock Knowledge Bases + Amazon S3 Vectors.

**Versioning, briefly.** A Guardrail's `DRAFT` is mutable; a numbered
version, created separately, is an immutable snapshot; runtime callers
reference a Guardrail by identifier + version. This module intentionally
does not own that lifecycle.

**How a consumer integrates one:**

```
terraform module (this one)
    |
    +-- knowledge_base_ids / knowledge_base_arns
    |
application / runtime (owned by the consumer)
    |
    +-- an existing Guardrail identifier + version
    |     (provisioned by another Terraform stack, by platform
    |      infrastructure, or manually - this module has no opinion)
    |
    +-- RetrieveAndGenerate(..., guardrailConfiguration = {...})
```

The Guardrail and the Knowledge Base are two independent resources that
meet only at the runtime call the consumer makes - never inside this
module's resource graph.
