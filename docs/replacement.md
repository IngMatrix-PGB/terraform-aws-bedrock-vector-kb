# Replacement Reference

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## Replacement / Lifecycle Reference

A compact reference for every `kbs[*]` field confirmed to force replacement
of a resource this module manages, consolidated in one place. Chunking and
S3 Vectors KMS encryption already have their own full explanations ([Chunking](chunking-and-embeddings.md#chunking), [S3 Vectors Encryption](encryption.md#s3-vectors-encryption)) - this table only summarizes them
alongside the fields newly documented here.

Two kinds of evidence appear below, and they are not the same strength:
**a schema fact** (a specific AWS/CloudFormation property is documented as
create-only, or a provider resource's own docs mark an argument `Forces new
resource`) versus **a dependency-graph conclusion** (reasoning about how a
replacement of one resource propagates into another, via a normal Terraform
attribute reference feeding a create-only argument on the downstream
resource). The schema facts are direct citations; the multi-resource
cascades built on top of them are this module's own reasoning about
Terraform's standard ForceNew-propagation behavior, not a statement AWS's
own documentation makes about cross-resource cascading (AWS's docs don't
discuss Terraform at all). Both are stated with confidence where the
reasoning is sound, but the two are labeled separately below rather than
folded into one blanket "proven" claim.

| Input | Affected resource | Replacement behavior | Operational consequence |
|---|---|---|---|
| `embedding_model_arn` | Knowledge Base, then Data Source | Schema fact: `KnowledgeBaseConfiguration`/`VectorKnowledgeBaseConfiguration` is a CloudFormation create-only property on `AWS::Bedrock::KnowledgeBase` - the Knowledge Base replaces. Dependency-graph conclusion built on that fact: the Data Source's `knowledge_base_id` argument references the KB's own `id` attribute, `KnowledgeBaseId` is independently create-only on `AWS::Bedrock::DataSource`, and a replaced KB is always assigned a new `id` (a certainty of how resource creation works, not a guess) - so the Data Source is forced to replace too, via ordinary Terraform ForceNew propagation. | New Knowledge Base and Data Source identifiers (`knowledge_base_ids`/`knowledge_base_arns`/`data_source_ids` outputs all change); full re-ingestion required. |
| `s3vectors_index_name`, `s3vectors_bucket_name` | Vector bucket/index, then Knowledge Base, then Data Source | Schema fact: both are `Forces new resource` on their own `aws` provider resources - the vector bucket/index replaces. Dependency-graph conclusion: a name change alters the index's own ARN string (the ARN embeds the bucket/index names, per AWS's own documented ARN format examples), which flows into the Knowledge Base's create-only `storage_configuration` - cascading by the same ForceNew-propagation reasoning as `embedding_model_arn` above. | Same as above: new KB/Data Source identifiers, full re-ingestion required. |
| `s3vectors_dimension`, `s3vectors_distance_metric`, `s3vectors_data_type` | Vector bucket/index | Schema fact: `Forces new resource` on both `aws` provider resources - the vector bucket/index replaces. The further Knowledge Base/Data Source cascade is **conditional, not live-verified** here: unlike a name change, the recreated index keeps the same bucket/index names, so its ARN string is likely unchanged - whether Terraform's planner still treats this as a changed value into the KB's create-only `storage_configuration` has not been confirmed against a live plan. See [S3 Vectors Encryption](encryption.md#s3-vectors-encryption) for the identical reasoning already established for `s3vectors_kms_key_arn`. | At minimum, vector data loss requiring re-ingestion; possibly also new KB/Data Source identifiers (unconfirmed). |
| `s3vectors_kms_key_arn` | Vector bucket/index, possibly Knowledge Base/Data Source | See [S3 Vectors Encryption](encryption.md#s3-vectors-encryption) - schema-fact bucket/index replacement, conditional (not live-verified) KB/Data Source cascade. | See [S3 Vectors Encryption](encryption.md#s3-vectors-encryption). |
| `chunking` | Data Source | Schema fact: `ChunkingConfiguration` is a CloudFormation create-only property on `AWS::Bedrock::DataSource` - the Data Source replaces directly, no cascade reasoning involved. See [Chunking](chunking-and-embeddings.md#chunking). | Data Source (not the KB) replaces; re-ingestion required. |

`kb_name`, `role_name`, `content_bucket`, KMS/logging/lifecycle fields not
listed above update in place or only affect resources with no replacement
semantics of their own.
