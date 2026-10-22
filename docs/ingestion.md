# Ingestion, Logging and IAM Boundaries

Part of the [terraform-aws-bedrock-vector-kb](../README.md) documentation.

## Bedrock / Ingestion Boundary

Terraform provisions Bedrock Knowledge Base **infrastructure** (the
Knowledge Base, the S3 Vectors store, the documents bucket, the data
source, IAM). It does **not** run ingestion, and it never will as a
`terraform apply` side effect - this is a deliberate architectural boundary,
not a gap this module is working toward closing.

Concretely, none of the following ever trigger ingestion:

- `terraform apply` itself, whether creating or updating any resource.
- Uploading, modifying, or deleting objects in the documents S3 bucket.
  Amazon Bedrock does not watch the bucket; nothing observes S3 events.
- Changing a `kbs` entry's `chunking` configuration. Even though this
  replaces the underlying data source (see [Chunking](chunking-and-embeddings.md#chunking)), the
  replacement itself does not re-ingest previously-ingested content.
- Creating the Knowledge Base or the data source for the first time.

`StartIngestionJob` is Bedrock's own imperative, one-shot API action - it
has no declarative Terraform resource in `hashicorp/aws` or
`hashicorp/awscc`, and no equivalent CloudFormation resource type exists
either, so `awscc` cannot gain one either. Every time documents in the
source bucket are added, modified, or removed, a new ingestion job must be
started explicitly (console, CLI, or SDK) to pick up the change. This
module does not use `null_resource`, `local-exec`, `remote-exec`, AWS CLI
invocations, Lambda, EventBridge, or Step Functions to work around that -
seemingly working around it would mean silently reintroducing the exact
imperative-inside-declarative anti-pattern this boundary exists to avoid.

See [Operational Lifecycle](operations.md#operational-lifecycle) for the complete sequence and flow
diagram, including how `ingestion_logging`/`APPLICATION_LOGS` and the
status outputs fit alongside this external workflow.

### Optional IAM support for that external workflow

This module can compute (but never creates or attaches) an IAM policy
document granting exactly the permissions that external workflow's "start
and monitor" step needs. Set `expose_ingestion_policy = true` on a `kbs`
entry to populate that entry's key in the `ingestion_policy_documents`
output:

```hcl
kbs = {
  default = {
    # ...required fields as above...
    expose_ingestion_policy = true
  }
}
```

What this does and does not do:

- **Creates:** nothing. `expose_ingestion_policy` computes a JSON policy
  document as a plain Terraform value (`jsonencode(...)`) - no
  `aws_iam_policy`, no attachment, no AWS API call. Omitting it (the
  default) leaves the output empty for that entry, exactly as before this
  field existed.
- **Does not attach to anything.** In particular, it is **not** added to
  this module's own Bedrock execution role
  (`aws_iam_role.bedrock_kb`/`iam_role_arns` output). That role is assumed
  *by the Bedrock service itself* to do its own internal work once an
  ingestion job is already running (invoke the embedding model, read S3
  documents, write to the vector store) - it is never the caller of
  `StartIngestionJob`, `GetIngestionJob`, or `ListIngestionJobs`. Those
  actions are called by whatever external principal (a CI role, an
  application role, a Lambda execution role, an operator's role) actually
  triggers and monitors ingestion, which this module cannot know and does
  not try to guess. Attach the resulting document (as a managed or inline
  policy) to whichever principal that is, in your own Terraform
  configuration or IAM tooling.
- **Grants exactly:** `bedrock:StartIngestionJob`, `bedrock:GetIngestionJob`,
  `bedrock:ListIngestionJobs`, scoped to that KB's own ARN (the real
  `knowledge_base_arn` attribute, not a hand-constructed string, so it is
  automatically correct for the deployed partition - `aws`, `aws-us-gov`,
  or `aws-cn`). Per AWS's IAM Service Authorization Reference for Amazon
  Bedrock, all three actions support resource-level permissions scoped only
  to the `knowledge-base` resource type - there is no finer-grained
  data-source- or ingestion-job-level ARN to scope to instead. This module
  currently creates exactly one data source per KB, but the scoping
  limit is AWS's own (any principal granted this policy can start/monitor
  ingestion for *any* data source under that KB, not a specific one) - not
  something this module chooses or could narrow further.
- **Never includes** `bedrock:*`, `s3:*`, `kms:*`, or any other wildcard
  action, regardless of whether the KB uses KMS, chunking, or anything
  else configured elsewhere in that same `kbs` entry.

## Ingestion Log Delivery

Amazon Bedrock Knowledge Bases can deliver `APPLICATION_LOGS` (per-document
ingestion status events - embedding started/completed/failed, indexing
started/completed/failed, and similar) through AWS's generic CloudWatch
Logs vended-log-delivery framework. This is infrastructure *configuration*,
not ingestion monitoring itself: **Terraform is not polling or watching
ingestion jobs here** - it is provisioning the pipe logs would flow
through, if and when an ingestion job runs (see [Bedrock / Ingestion Boundary](#bedrock--ingestion-boundary) for the boundary on triggering/monitoring ingestion
itself). This is a distinct concept from the [Operational Status Outputs](operations.md#operational-status-outputs): those reflect Terraform's own refresh-time state of the KB/data
source resources; `APPLICATION_LOGS` are operational ingestion/document
events delivered externally, by AWS, outside Terraform's state entirely.

**Ownership boundary:** this module creates exactly two resources per
opted-in `kbs` entry:
- `aws_cloudwatch_log_delivery_source` - registers the KB itself (by its
  real `knowledge_base_arn`) as a source of `APPLICATION_LOGS`.
- `aws_cloudwatch_log_delivery` - links that source to a destination.

This module **never creates** the delivery destination - no
`aws_cloudwatch_log_delivery_destination`, no CloudWatch Logs log group, no
S3 bucket, no Data Firehose stream, and no destination policy. You supply
an **existing** destination's ARN; AWS itself requires that destination to
already exist (it is never auto-provisioned), so there is nothing for this
module to bootstrap even if it wanted to.

**`delivery_destination_arn` is the AWS Logs `DeliveryDestination` ARN -
not the physical resource it points at.** It is **not directly**:
- a CloudWatch Log Group ARN,
- an S3 bucket ARN, or
- a Data Firehose delivery stream ARN.

The `DeliveryDestination` is its own logical AWS Logs object (created by
you, outside this module, via `PutDeliveryDestination`/
`aws_cloudwatch_log_delivery_destination`/`awscc_logs_delivery_destination`)
that *wraps* one of those physical resources. Its ARN looks like
`arn:aws:logs:<region>:<account>:delivery-destination:<name>` - not
`arn:aws:logs:...:log-group:...`, `arn:aws:s3:::...`, or
`arn:aws:firehose:...`. Passing a physical resource's own ARN here will not
work; you must create the `DeliveryDestination` object first and pass
*its* ARN.

**The document bucket this module creates
(`aws_s3_bucket.kb_docs`/`content_bucket`) is never the ingestion log
destination, automatically or by any default.** It holds Knowledge Base
source documents; `ingestion_logging.delivery_destination_arn` is an
entirely separate, consumer-chosen destination for operational logs. This
module does not couple them, and does not recommend doing so - the two
have different retention/lifecycle needs and no relationship to each
other beyond both belonging to the same KB.

**Delivery source naming:** the delivery source is named deterministically
as `"${kb_name}-ingestion-logs"` - no random suffix. `PutDeliverySource`
requires this name to be 1-60 characters, matching `[\w-]*` (letters,
digits, underscore, hyphen), and unique across all delivery sources in
your account/region. This module validates the derived name's length at
`terraform plan` time when `ingestion_logging` is set (`kb_name` itself has
no length limit of its own beyond AWS's 100-character KB name limit, so a
long `kb_name` plus the `-ingestion-logs` suffix can exceed 60 characters -
shorten `kb_name` for that entry if this happens). A charset check exists
too, but is effectively unreachable in practice: `kb_name` itself is
already constrained by `awscc_bedrock_knowledge_base`'s own name pattern
(`^([0-9a-zA-Z][_-]?){1,100}$`), whose character set is always a subset of
`[\w-]*` - there is no `kb_name` value the KB resource itself would accept
that could fail this derived-name check on character content alone.

```hcl
kbs = {
  default = {
    # ...required fields as above...

    ingestion_logging = {
      delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:my-existing-destination"
    }
  }
}
```

Omitting `ingestion_logging` (the default) creates neither resource.

**Destinations**: CloudWatch Logs, S3, and Data Firehose are all supported
- AWS infers the destination type from the ARN itself, so this module has
no separate "destination type" field to set. **Same-account only** for
now; cross-account delivery (which needs a
`PutDeliveryDestinationPolicy`-configured resource policy on the
destination) is not implemented.

**Shared destinations are explicitly supported, with no special
configuration.** AWS's own API is designed so that multiple delivery
sources can send to the same delivery destination - two (or more) `kbs`
entries may intentionally set the identical `delivery_destination_arn`:

```hcl
kbs = {
  a = { # ...
    ingestion_logging = { delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:shared" }
  }
  b = { # ...
    ingestion_logging = { delivery_destination_arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:shared" }
  }
}
```
This creates two independent `aws_cloudwatch_log_delivery_source`/
`aws_cloudwatch_log_delivery` pairs (one per KB, as always), both pointing
at the one destination you already own - no deduplication logic is needed
or attempted, since the module never owned that shared resource in the
first place.

`ingestion_log_delivery_source_arns` and `ingestion_log_delivery_arns`
expose the two created resources' ARNs, keyed by `kbs` entry, for anyone
building their own auditing/monitoring around this (e.g. calling
`logs:GetDeliverySource`/`logs:GetDelivery` directly, or referencing these
ARNs in their own IAM policies).

### Apply-time permissions for ingestion logging

Creating these two resources requires the identity running `terraform
apply` (not this module's Bedrock execution role, and not a principal this
module creates) to hold, at minimum:

- `bedrock:AllowVendedLogDeliveryForResource`, scoped to the specific KB
  ARN - AWS classifies this as a permissions-management action, checked
  when `PutDeliverySource` names that KB as the source resource.
- `logs:PutDeliverySource`, `logs:GetDeliverySource`,
  `logs:DeleteDeliverySource`, scoped to the delivery-source ARN this
  module will create (`arn:aws:logs:<region>:<account>:delivery-source:<kb_name>-ingestion-logs`).
- `logs:CreateDelivery`, `logs:GetDelivery`, `logs:DeleteDelivery`, which
  need the delivery, delivery-destination, *and* delivery-source ARNs
  together.
- Whatever permission the destination itself requires to be named in a
  delivery (e.g. `logs:PutDeliveryDestination` is **not** needed by this
  module since it never creates a destination, but the destination's own
  owner may separately need it when *they* set it up).

This module does not grant any of these - they are prerequisites for
whoever runs `terraform apply`, exactly like the S3/IAM/KMS permissions
already required to create every other resource in this module. Do not
attach these to `aws_iam_role.bedrock_kb`; that role is never the caller of
any of these APIs.

## Logging Boundary

`logging_target_bucket` is bring-your-own: this module never creates or
configures the destination logging bucket. The consumer is responsible for
ensuring that destination bucket is set up to accept S3 server access log
delivery (the appropriate bucket policy/permissions for the S3 log delivery
service). If it isn't, log delivery will simply fail silently on the AWS
side - this module cannot detect or prevent that.

## IAM Boundaries

Two entirely separate IAM boundaries exist in this module's contract - do
not conflate them:

**A. Ingestion runtime actor.** The principal that actually calls
`bedrock:StartIngestionJob`/`GetIngestionJob`/`ListIngestionJobs` owns
those runtime permissions itself. This module may *expose* a
least-privilege policy JSON for that principal to use
(`ingestion_policy_documents`, when `expose_ingestion_policy = true`), but
never attaches it to anything. See [Optional IAM support for that external workflow](#optional-iam-support-for-that-external-workflow).

**B. Terraform apply identity.** Creating/configuring the two
`ingestion_logging` resources requires the identity running `terraform
apply` to hold control-plane permissions for log delivery configuration
(`bedrock:AllowVendedLogDeliveryForResource`, `logs:PutDeliverySource`,
`logs:CreateDelivery`, and related actions). See [Apply-time permissions for ingestion logging](#apply-time-permissions-for-ingestion-logging).

Neither boundary's permissions belong on `aws_iam_role.bedrock_kb` - that
role is the Bedrock service's own execution role, assumed by Bedrock
itself during an already-running ingestion job, and is never the caller of
any action in either boundary A or B. This module never publishes or
recommends a broad `bedrock:*`/`logs:*` policy for either boundary; both
sections above list exact, scoped actions.
