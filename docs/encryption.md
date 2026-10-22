# Encryption

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## KMS Boundary

`kms_key_arn` is bring-your-own-key: this module never creates or manages a
KMS key. When set, the module grants the Bedrock execution role
`kms:Decrypt` and `kms:GenerateDataKey`, scoped to exactly that key ARN.
That identity-policy grant is necessary but **not sufficient** on its own -
the external key's own key policy must separately allow the Bedrock
execution role. Passing `kms_key_arn` does not, by itself, guarantee
successful KMS access; the key policy is the consumer's responsibility.

## S3 Vectors Encryption

**Warning: encryption settings cannot be changed after the vector bucket or
vector index is created.** This is an AWS limitation, not a choice this
module makes.

**Proven:** setting `s3vectors_kms_key_arn` on a `kbs` entry that already
has a module-created, unencrypted vector bucket/index (`create_s3vectors =
true`) will force Terraform to **replace** both
`aws_s3vectors_vector_bucket` and `aws_s3vectors_index` - destroying and
recreating them, since `encryption_configuration` is independently
`Forces new resource` on each. A replaced vector index has **no vectors in
it** until documents are re-ingested (`StartIngestionJob`, external to this
module - see [Operational Lifecycle](operations.md#operational-lifecycle)); this module does not detect, warn
about, or automate that re-ingestion.

**Conditional, not yet live-verified:** the Knowledge Base's
`storage_configuration` (which carries the S3 Vectors index ARN) is a
CloudFormation `createOnlyProperty` on `AWS::Bedrock::KnowledgeBase`.
Because the Knowledge Base storage configuration is create-only, a change
in the *effective* S3 Vectors index ARN would also require Knowledge Base
replacement. With this module's current deterministic index naming (the
recreated index keeps the same bucket/index names, and S3 Vectors index
ARNs are name-based, so the ARN string is likely unchanged across the
replacement), whether Terraform's planner actually treats this as a
changed value - and therefore plans that additional Knowledge Base
replacement - has **not yet been verified with a live AWS plan**. If it
does cascade: the Knowledge Base's `KnowledgeBaseId`/ARN would change,
external consumers of the `knowledge_base_ids`/`knowledge_base_arns`
outputs would need to account for that, and the KB's Data Source would
very likely also require replacement, since a Data Source belongs to a
specific Knowledge Base ID.

Either way - proven or conditional - re-ingestion is required afterward.
Plan this change deliberately, on a maintenance window, with re-ingestion
ready to run immediately after apply - do not treat it as a routine,
safe-to-apply-anytime input change like most other optional fields in this
module.

`s3vectors_kms_key_arn` is bring-your-own-key, exactly like the docs
bucket's `kms_key_arn` above, but it is an **independent security
boundary**: the two may use different keys, and setting one never requires
or implies setting the other. Default (`null`, omitted) leaves AWS's own
default encryption unchanged. Only applies when `create_s3vectors = true` -
this module has no way to know or change the encryption state of an
externally-provided `s3vectors_index_arn`.

When set, this module grants the Bedrock execution role **`kms:Decrypt`
only** (not `kms:GenerateDataKey`, unlike the docs-bucket policy above) on
exactly that key ARN, as a logically separate IAM policy from the docs
bucket's KMS policy. This is a deliberate, evidence-based choice, not an
oversight: AWS's own S3 Vectors encryption documentation explicitly names
`kms:Decrypt` as the permission IAM principals need to access a
KMS-encrypted vector bucket/index - no AWS source found names any
additional action, so none is granted speculatively. That said, this is
the boundary of what's currently verified: native `terraform test` cases
validate the IAM/HCL shape only (the policy's action, effect, and
resource scoping), not live AWS behavior; AWS's documentation does not
explicitly settle whether the complete Bedrock → S3 Vectors *write* path
needs anything beyond `kms:Decrypt`. Live AWS integration validation
remains future work. As with `kms_key_arn`, this identity-policy grant is
necessary but **not sufficient** on its own - the external key's own key
policy must separately allow the Bedrock execution role.

This module sets the same `s3vectors_kms_key_arn` explicitly on **both**
the vector bucket and its index, rather than setting it once on the bucket
and relying on the index's own encryption inheriting from the bucket. AWS's
own console documentation for configuring vector index encryption presents
an explicit "use bucket settings for encryption" choice, suggesting
inheritance is supported; the `aws` provider's own resource documentation
for the vector index instead describes its `sse_type` as defaulting to
`AES256` when its `encryption_configuration` block is omitted, with no
inheritance language. These two authoritative sources do not fully agree,
and this module resolves the ambiguity by setting the key explicitly on
both resources - the one choice that guarantees full encryption of the
entire S3 Vectors storage stack regardless of how that discrepancy
resolves, rather than risk an under-encrypted index by assuming
inheritance.
