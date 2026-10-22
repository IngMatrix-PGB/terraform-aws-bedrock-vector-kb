# Operations

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## Operational Lifecycle

This module provisions infrastructure. It does not orchestrate what happens
to that infrastructure afterward. The sequence below is the complete,
consolidated picture of how a `terraform apply` relates to the pieces this
module can also configure (ingestion IAM policy documents, ingestion log
delivery, status outputs) - each piece is documented in full further down;
this section exists to make the overall shape and the control-plane/runtime
boundary unmistakable in one place.

1. `terraform apply` provisions or updates the Knowledge Base, Data Source,
   S3 Vectors store, documents bucket, and IAM - the infrastructure this
   module owns.
2. Documents are uploaded or updated in the Knowledge Base's document S3
   bucket (`content_bucket`), by whatever process manages your documents.
   This is entirely outside this module and outside `terraform apply`.
3. **S3 document changes do not automatically update the Knowledge Base's
   vector index.** Amazon Bedrock does not watch the bucket.
4. An external actor (not Terraform) invokes `bedrock:StartIngestionJob`,
   using `knowledge_base_ids["<key>"]` and `data_source_ids["<key>"]` as the
   required `knowledgeBaseId`/`dataSourceId` parameters. If
   `expose_ingestion_policy = true`, `ingestion_policy_documents["<key>"]`
   is the least-privilege policy JSON for that actor to use - see [IAM Boundaries](ingestion.md#iam-boundaries) for who actually attaches and calls it.
5. That same (or another) external actor can inspect ingestion execution
   through `bedrock:GetIngestionJob` and `bedrock:ListIngestionJobs`.
6. When `ingestion_logging` is configured for that KB, AWS emits
   `APPLICATION_LOGS` through the chain this module builds:
   module-created `DeliverySource` → module-created `Delivery` →
   consumer-owned `DeliveryDestination`. See [Ingestion Log Delivery](ingestion.md#ingestion-log-delivery).
7. `knowledge_base_statuses` and `data_source_statuses` reflect
   provider-observed control-plane state as of the most recent Terraform
   `refresh`/`plan`/`apply` - they are **not** ingestion-job polling,
   continuous monitoring, or a real-time health check. See
   [Operational Status Outputs](#operational-status-outputs) for how this differs from ingestion job status.
8. Once ingestion succeeds, runtime consumers may retrieve against the
   updated Knowledge Base (`Retrieve`/`RetrieveAndGenerate`) - this is
   application-level runtime behavior, entirely outside this module.

```
                    terraform apply
                          |
                          v
        +------------------------------------+
        | Bedrock Knowledge Base              |
        | Data Source                         |
        | S3 Vectors                          |
        +------------------------------------+
                          ^
                          |
                  documents in S3
                          |
                          | external actor calls
                          | StartIngestionJob
                          v
                  Bedrock ingestion
                    /            \
                   /              \
      Get/ListIngestionJob     APPLICATION_LOGS
       (external polling)             |
                                       v
                              DeliverySource (module)
                                       |
                                       v
                                Delivery (module)
                                       |
                                       v
                       DeliveryDestination (consumer-owned)

                  successful ingestion
                          |
                          v
              runtime retrieval / application
```

Terraform is never the caller of `StartIngestionJob`, `GetIngestionJob`, or
`ListIngestionJobs` anywhere in this flow.

## Responsibility Matrix

| Concern | Module owns | Consumer owns | Notes |
|---|---|---|---|
| Knowledge Base | ✅ | | `awscc_bedrock_knowledge_base` |
| Data Source | ✅ | | `awscc_bedrock_data_source` |
| S3 Vectors index | ✅ (or bring-your-own) | ✅ (if bring-your-own) | `create_s3vectors` toggles which |
| Document S3 bucket | ✅ | | Source documents only - never the ingestion log destination |
| Chunking configuration | ✅ | | Validated at `plan` time; see [Chunking](chunking-and-embeddings.md#chunking) |
| Embedding/dimension validation | ✅ | | Static known-model map; see [Embedding Model / Dimension Compatibility](chunking-and-embeddings.md#embedding-model--dimension-compatibility) |
| `StartIngestionJob` execution | | ✅ | No Terraform resource exists for this; see [Operational Lifecycle](#operational-lifecycle) |
| `Get`/`ListIngestionJobs` polling | | ✅ | Runtime operational behavior |
| Ingestion IAM policy document generation | ✅ | | `ingestion_policy_documents`, only when `expose_ingestion_policy = true` |
| Ingestion IAM policy attachment | | ✅ | Module never attaches it to any principal |
| Ingestion caller principal | | ✅ | CI role, app role, Lambda role, operator role - module has no opinion |
| `APPLICATION_LOGS` `DeliverySource` | ✅ | | `aws_cloudwatch_log_delivery_source`, only when `ingestion_logging` is set |
| `APPLICATION_LOGS` `Delivery` | ✅ | | `aws_cloudwatch_log_delivery`, only when `ingestion_logging` is set |
| `DeliveryDestination` | | ✅ | Module only accepts an existing `delivery_destination_arn` - never creates one |
| Physical log destination (log group / bucket / Firehose stream) | | ✅ | Must already exist; AWS never auto-provisions it |
| CloudWatch alarms | | ✅ | Not implemented by this module at all |
| CloudTrail account-level configuration | | ✅ | Management events are logged automatically by AWS regardless; this module configures nothing here |
| Runtime retrieval/application (`Retrieve`/`RetrieveAndGenerate`) | | ✅ | Entirely outside this module |
| Bedrock Guardrails (creation, versioning, runtime selection) | | ✅ | No Terraform resource created by this module; see [Guardrails Integration Boundary](guardrails.md#guardrails-integration-boundary) |

When `expose_ingestion_policy = true`, the module generates
`ingestion_policy_documents` - but the consumer still owns the caller
principal, the policy attachment, the invocation, and the polling. The
module never crosses from "generate the JSON" into "make something use
it."

## Operational Status Outputs

`knowledge_base_statuses` and `data_source_statuses` expose each resource's
`status`/`data_source_status` attribute, keyed by `kbs` entry. Both are
plain computed-attribute passthroughs - no polling, no new IAM, no new AWS
resource.

**Three different status concepts exist across this module's contract -
they are not interchangeable:**

| | Concept | Source | Nature |
|---|---|---|---|
| A | Knowledge Base infrastructure status | `knowledge_base_statuses` | Terraform/provider-observed control-plane state |
| B | Data Source infrastructure status | `data_source_statuses` | Terraform/provider-observed control-plane state |
| C | Ingestion job execution status | `GetIngestionJob`/`ListIngestionJobs` | Runtime operational state, entirely outside Terraform |

A and B answer "does the KB/Data Source *resource itself* exist and is it
in a healthy state, as of the last Terraform refresh/apply?" - never "is my
ingestion job finished?" or "did my documents get indexed?" That is
exclusively C's question, and C is not something this module reads,
computes, or exposes in any form - it requires calling
`GetIngestionJob`/`ListIngestionJobs` directly (see [Operational Lifecycle](#operational-lifecycle)).

**Status outputs reflect the most recently refreshed Terraform state and
should not be treated as continuous monitoring.** Terraform captures these
values during `refresh`/`plan`/`apply` - the value can be stale the moment
the run finishes if the underlying resource's real AWS state changes
afterward (for example, a Knowledge Base transitioning to `FAILED` between
one `apply` and the next). Re-run `terraform plan` or `terraform refresh`
to get a current value. These are not real-time status, not live health,
and not a substitute for actual monitoring - see [Bedrock / Ingestion Boundary](ingestion.md#bedrock--ingestion-boundary) for what this module deliberately does not do
(CloudWatch/CloudTrail/EventBridge integration is a separate, future
concern, not implemented by this output).

Documented status values, per AWS's current API reference (not
exhaustive-by-omission if AWS adds more later):
- Knowledge Base (`knowledge_base_statuses`): `CREATING`, `ACTIVE`,
  `DELETING`, `UPDATING`, `FAILED`, `DELETE_UNSUCCESSFUL`,
  `UPDATE_UNSUCCESSFUL`.
- Data source (`data_source_statuses`): `AVAILABLE`, `DELETING`,
  `DELETE_UNSUCCESSFUL`, `CREATING`, `UPDATING`, `FAILED`.

`data_source_ids` closes an operational gap left open by v0.2.0: an
external actor calling `StartIngestionJob` (see [Bedrock / Ingestion Boundary](ingestion.md#bedrock--ingestion-boundary)) needs both `knowledgeBaseId` and `dataSourceId` as path
parameters. `knowledge_base_ids` already provided the former; this module
had no output for the latter until now. This output does not change the
ingestion boundary - Terraform still never calls `StartIngestionJob`
itself - it only gives the external workflow the second identifier that
workflow already required.

## Lifecycle Semantics

**Always enabled**, with no opt-out:
- Abort incomplete multipart uploads after 7 days.

**Opt-in only**, via `noncurrent_version_expiration_days`:
- Noncurrent-version expiration. `null` (the default) means this module
  preserves noncurrent object versions indefinitely - it never deletes them
  on its own. Setting this to a number of days is genuinely destructive
  retention behavior: it permanently deletes old version content once it
  ages past that threshold. It never touches the current/live version of an
  object, but the deletion of noncurrent versions themselves is real and
  irreversible, which is why it is opt-in rather than a default.

## Troubleshooting: Stale Retrieval Results

If a `Retrieve`/`RetrieveAndGenerate` call isn't reflecting a document you
just added or changed, work through this sequence - **`terraform apply`
does not trigger document re-ingestion**, so it is never the fix by itself:

1. Confirm the document was actually uploaded or updated in the content
   bucket (`content_bucket`).
2. Confirm `StartIngestionJob` was actually invoked afterward, by the
   external actor responsible for it - a document sitting in S3 with no
   ingestion job run against it will never appear in retrieval results.
3. Inspect `GetIngestionJob`/`ListIngestionJobs` for that data source to
   confirm the job reached `COMPLETE` (not `FAILED`, `STOPPED`, or still
   `IN_PROGRESS`).
4. If `ingestion_logging` is configured, inspect the delivered
   `APPLICATION_LOGS` for that document - per-document status events
   (`EMBEDDING_FAILED`, `INDEXING_FAILED`, etc.) will usually explain a
   silent failure that `GetIngestionJob`'s summary alone might not make
   obvious.
5. Only when investigating infrastructure/control-plane state (is the KB
   or Data Source itself healthy, not "did my documents get indexed"),
   inspect `knowledge_base_statuses`/`data_source_statuses` - and re-run
   `terraform plan`/`refresh` first, since these are refresh-time
   snapshots, not live values.
6. Once ingestion is confirmed successful (step 3), investigate runtime
   retrieval behavior itself (query text, retrieval configuration,
   application-level caching) - that is outside this module's scope
   entirely.
