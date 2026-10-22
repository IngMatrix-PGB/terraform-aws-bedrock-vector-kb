# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-10-22

Security hardening for the Bedrock execution role and the documents
bucket. Backward compatible: no new required inputs, no changed resource
addresses. Existing deployments get an in-place update of the trust policy
and S3 read policy, plus one new `aws_s3_bucket_ownership_controls`
resource per KB.

### Added

- `content_bucket_arns` output: the documents bucket ARN per `kbs` key, so
  callers can grant their upload process `s3:PutObject` without rebuilding
  the ARN themselves.
- `aws_s3_bucket_ownership_controls.kb_docs` with `BucketOwnerEnforced`:
  ACLs are disabled on the documents bucket, so access is governed only by
  IAM and the bucket policy.

### Security

- The Bedrock execution role's trust policy now carries confused-deputy
  conditions (`aws:SourceAccount` and `aws:SourceArn` scoped to Knowledge
  Bases in this account and region), matching AWS's service role example
  for Knowledge Bases. Existing roles are updated in place (no
  replacement). A Knowledge Base in another account or region can no
  longer get Bedrock to assume this role.
- The S3 read policy is pinned to this account with `aws:ResourceAccount`.
  S3 bucket names are global; without it, a same-named bucket in another
  account would also match the policy.

### Fixed

- IAM ARNs for the documents bucket were hardcoded to the `aws` partition,
  so the module produced wrong ARNs in GovCloud (`aws-us-gov`) and China
  (`aws-cn`). They are now built from `data.aws_partition`.
- `examples/basic` still said no release tag existed; it now shows how to
  pin a tag.

## [1.0.0] - 2026-08-31

This release declares the public module API - the `kbs[*]` input schema,
all outputs, and Terraform resource addresses - **stable** for the 1.x
release line. v1.0.0 is a public-API-stability milestone, not a
feature-completeness, production-certification, or AWS-certification
claim: see "Definition of Production-Oriented" in the release
certification for what "production-oriented" does and does not mean for
this module. No Guardrails, Agents, automatic ingestion, additional vector
store backend, new IAM permission, or new infrastructure resource is
introduced by this release - every change below is fail-fast validation
and documentation hardening identified during the v1.0.0 readiness review.

### Added

- Two new `kbs` variable validations closing a real, previously-silent gap
  as part of the v1.0.0 API freeze: `kbs[*].kb_name` must produce a derived
  Bedrock Data Source name (`"${kb_name}-docs"`) that matches
  `AWS::Bedrock::DataSource`'s exact Name pattern
  (`^([0-9a-zA-Z][_-]?){1,100}$` - a repetition-count bound, not a fixed
  raw-character-count limit, since each optional separator lets two raw
  characters share one repetition), and must not end in `-`/`_` (which
  would produce an invalid double-separator sequence once the literal
  `-docs` suffix is appended, independent of length). Both fire
  unconditionally for every `kbs` entry, since the Data Source name is
  always derived, not opt-in. Neither restricts `kb_name` in general -
  only the derived name this module itself constructs.
- 5 new native `terraform test` cases covering: a 96-character
  separator-free `kb_name` (the true boundary - passes), a 97-character
  separator-free `kb_name` (fails), a 149-character `kb_name` using
  internal separators (still passes, proving no fixed length threshold is
  correct for every composition), and `kb_name` ending in `-` or `_`
  (fails).

### Documentation

- New "Replacement / Lifecycle Reference" README section: a compact table
  covering every `kbs[*]` field confirmed to force replacement of a
  module-managed resource, including two fields not previously documented
  (`embedding_model_arn` and `s3vectors_index_name`/`s3vectors_bucket_name`,
  each a direct CloudFormation/provider create-only fact for the resource
  it changes directly, cascading into Knowledge Base and Data Source
  replacement by ordinary Terraform dependency/ForceNew-propagation
  reasoning - a distinct, separately-labeled kind of evidence from the
  direct schema fact itself) and
  `s3vectors_dimension`/`s3vectors_distance_metric`/`s3vectors_data_type`
  (a direct create-only fact for the vector bucket/index; a further
  Knowledge Base/Data Source cascade remains conditional and not
  live-verified, the same distinction already established for
  `s3vectors_kms_key_arn`, which this entry does not alter).
  Cross-references the existing "Chunking" and "S3 Vectors Encryption"
  sections rather than duplicating them. No Terraform behavior changed by
  this entry - documentation only.

## [0.4.0] - 2026-08-31

### Added

- New optional `s3vectors_kms_key_arn` field on each `kbs` entry
  (bring-your-own KMS key, default `null`). Only applies when
  `create_s3vectors = true`. When set, this module creates an
  `encryption_configuration` block (`sse_type = "aws:kms"`,
  `kms_key_arn = <supplied ARN>`) on **both** the module-created
  `aws_s3vectors_vector_bucket` and `aws_s3vectors_index` explicitly - not
  relying on the index's own encryption inheriting from the bucket, since
  AWS's console documentation and the `aws` provider's own resource
  documentation for the vector index do not fully agree on whether that
  inheritance is the default when the index's `encryption_configuration`
  is omitted. This is an independent security boundary from the existing
  `kms_key_arn` (documents bucket) - the two may use different keys, and
  setting one never requires or implies setting the other.
- New, separate IAM policy (`aws_iam_policy.s3vectors_kms` +
  `aws_iam_role_policy_attachment.s3vectors_kms`) granting the Bedrock
  execution role `kms:Decrypt` only, scoped to exactly the supplied
  `s3vectors_kms_key_arn`, only when it is set. Deliberately does **not**
  include `kms:GenerateDataKey` (unlike the existing docs-bucket KMS
  policy): AWS's own S3 Vectors encryption documentation names only
  `kms:Decrypt` as the permission IAM principals need, and the AWS IAM
  Service Authorization Reference for `s3vectors` shows no KMS-related
  condition key or dependency on any of the S3 Vectors data-plane actions
  (`PutVectors`/`GetVectors`/`QueryVectors`/`DeleteVectors`/`GetIndex`/
  `ListVectors`) - only `CreateVectorBucket`/`CreateIndex` reference KMS at
  all, and only as IAM condition keys restricting what may be specified at
  creation, not as evidence of a runtime permission requirement. As with
  the existing docs-bucket KMS grant, this identity-policy grant is
  necessary but not sufficient on its own - the external key's own key
  policy must separately allow the Bedrock execution role.
- 15 new native `terraform test` cases covering: default (zero encryption
  resources/policies), exact `encryption_configuration`/`kms_key_arn`/
  `sse_type` wiring on both the vector bucket and index, multiple KBs with
  independent keys, two KBs intentionally sharing one key, `enable_kbs =
  false`, independence from the existing docs-bucket `kms_key_arn` in both
  directions, interaction with chunking/`ingestion_logging`/
  `expose_ingestion_policy` (including a regression proving no `kms:*`
  action leaks into `ingestion_policy_documents`), operational-outputs
  regression, empty/whitespace `s3vectors_kms_key_arn` (hard validation
  failure), exact IAM action/effect/policy-separation assertions, and a
  v0.3.0-style configuration regression.

### Security

- **Replacement risk**: AWS documents S3 Vectors encryption settings as
  unable to change after the vector bucket/index is created. Setting
  `s3vectors_kms_key_arn` on an existing, unencrypted `kbs` entry
  (`create_s3vectors = true`) will force Terraform to replace both
  `aws_s3vectors_vector_bucket` and `aws_s3vectors_index` (proven),
  destroying all existing vectors; re-ingestion (external to this module)
  is required afterward. A further Knowledge Base/Data Source replacement
  cascade is also possible, since the Knowledge Base's
  `storage_configuration` is a CloudFormation create-only property, but
  this has not yet been verified against a live AWS plan. See the
  README's "S3 Vectors Encryption" section for the full warning.

### Documentation

- Documented the runtime ownership boundary for Amazon Bedrock Guardrails
  and Knowledge Bases: a new "Guardrails Integration Boundary" README
  section explains that Knowledge Base/Data Source resources expose no
  declarative Guardrail attachment point, where Guardrails are actually
  configured (`Retrieve`, `RetrieveAndGenerate`, Bedrock Agents), what a
  Guardrail evaluates versus what it does not, and how a consumer
  integrates an externally-provisioned Guardrail at runtime. Cross-
  referenced from the Responsibility Matrix and Known Limitations. No
  Terraform behavior changed - this entry is documentation only, and no
  Guardrail support was added.

## [0.3.0] - 2026-08-31

### Added

- New outputs `knowledge_base_statuses` and `data_source_statuses`, plain
  computed-attribute passthroughs (`status`/`data_source_status`) keyed by
  `kbs` entry. These reflect the most recently refreshed Terraform state
  only - not continuous monitoring, polling, or a real-time health check.
  No new resources, no new IAM.
- New output `data_source_ids`, keyed by `kbs` entry. Closes an operational
  gap left open since v0.2.0: an external actor calling `StartIngestionJob`
  needs both `knowledgeBaseId` (already available via `knowledge_base_ids`)
  and `dataSourceId`, which had no output until now. This does not change
  the ingestion boundary - Terraform still never calls `StartIngestionJob`.
- 12 new native `terraform test` cases covering all three new outputs
  (single KB, multiple independently-keyed KBs, `enable_kbs = false` empty
  shape), regression coverage proving `knowledge_base_ids`,
  `knowledge_base_arns`, and `ingestion_policy_documents` are unchanged, and
  interaction coverage with chunking, model/dimension validation, and
  `expose_ingestion_policy`.
- New optional `ingestion_logging` field on each `kbs` entry
  (`{ delivery_destination_arn = string }`), creating an
  `aws_cloudwatch_log_delivery_source` and `aws_cloudwatch_log_delivery` to
  send that KB's `APPLICATION_LOGS` (per-document ingestion status events)
  to an existing CloudWatch Logs, S3, or Data Firehose destination. This
  module never creates the destination itself - no log group, bucket,
  Firehose stream, `aws_cloudwatch_log_delivery_destination`, or
  destination policy. Multiple `kbs` entries may intentionally share the
  same destination ARN; no deduplication logic is needed since the shared
  resource was never module-owned. New outputs
  `ingestion_log_delivery_source_arns` and `ingestion_log_delivery_arns`.
- 12 new native `terraform test` cases covering: default (zero resources),
  single-KB exact wiring (`log_type`, `resource_arn`, deterministic naming,
  destination ARN), mixed multi-KB opt-in, two KBs intentionally sharing
  one destination, two KBs with distinct destinations, `enable_kbs = false`
  (zero resources), empty/whitespace `delivery_destination_arn` (hard
  validation failure), and interaction coverage with chunking, model/
  dimension validation, `expose_ingestion_policy`, the PR #14 operational
  status outputs, and KMS.

### Security

- Documented (not granted) the apply-time IAM permissions
  `bedrock:AllowVendedLogDeliveryForResource` and the `logs:*DeliverySource`/
  `logs:*Delivery` actions needed to create the two new resources. These
  are prerequisites for whoever runs `terraform apply` - this module does
  not attach them to `aws_iam_role.bedrock_kb` or any other principal it
  creates.

### Known Limitations

- `ingestion_logging` does not create the delivery destination
  (CloudWatch Logs, S3, or Data Firehose) - the caller must already own
  one, since AWS's own API requires the destination to pre-exist.
- Same-account delivery only; cross-account delivery destinations (which
  require a `PutDeliveryDestinationPolicy`-configured resource policy on
  the destination) are not implemented.
- The derived delivery source name (`"${kb_name}-ingestion-logs"`) must fit
  AWS's 60-character limit for delivery source names; this module validates
  that at `terraform plan` time rather than letting AWS reject it later.

### Documentation

- Consolidated the operational contract established across PR #14
  (operational status outputs) and PR #15 (ingestion log delivery) into
  the README: a new "Operational Lifecycle" section (the complete,
  numbered sequence from `terraform apply` through document upload,
  external `StartIngestionJob`, `APPLICATION_LOGS` delivery, and runtime
  retrieval, plus a consolidated flow diagram replacing the smaller
  duplicate one previously in "Bedrock / Ingestion Boundary"); a new
  "Responsibility Matrix" table covering every concern this module and its
  consumers touch; a new "IAM Boundaries" section distinguishing the
  ingestion runtime actor's permissions from the Terraform apply
  identity's permissions; a new "Troubleshooting: Stale Retrieval Results"
  workflow; an explicit three-way distinction between Knowledge Base
  status, Data Source status, and ingestion job execution status (added to
  "Operational Status Outputs"); and an explicit clarification that
  `ingestion_logging.delivery_destination_arn` is the AWS Logs
  `DeliveryDestination` ARN itself, not the physical log
  group/bucket/Firehose-stream ARN it wraps, and that the document bucket
  is never an implicit ingestion log destination (added to "Ingestion Log
  Delivery"). "Known Limitations" was updated to include the ingestion
  logging and status-output limitations introduced by PR #14/#15, which
  had previously only been recorded in this Changelog. No Terraform
  behavior changed - this entry is documentation only.

## [0.2.0] - 2026-08-30

### Added

- Optional `chunking` configuration on each `kbs` entry, supporting all four
  AWS-documented strategies (`FIXED_SIZE`, `HIERARCHICAL`, `SEMANTIC`,
  `NONE`), wired into `awscc_bedrock_data_source`'s
  `vector_ingestion_configuration`. Validation enforces AWS's documented
  per-strategy exclusivity and numeric ranges at `terraform plan` time,
  since the provider/CloudFormation schemas only document these
  constraints in prose and otherwise fail late, at `apply`, with an opaque
  `ValidationException`.
- 13 new native `terraform test` cases covering omission (regression),
  each valid strategy, each documented invalid range, invalid level counts
  for `HIERARCHICAL`, mixed/invalid strategy combinations, and multiple
  `kbs` entries using different strategies independently.
- Embedding model / vector dimension compatibility validation: each `kbs`
  entry's `embedding_model_arn` / `s3vectors_dimension` pair is checked at
  `terraform plan` time against a small internal map of models AWS
  documents as supported for Knowledge Bases' vector embeddings. A known
  model with an unsupported dimension fails early with a specific,
  actionable message (model, configured dimension, allowed dimensions); a
  model this module does not recognize always passes, so a new AWS model
  never breaks the module. New optional `skip_dimension_validation` field
  (default `false`) on each `kbs` entry, an explicit escape hatch for a
  recognized model when the maintained map is stale.
- 18 new native `terraform test` cases covering every model currently in
  the compatibility map (valid and invalid dimensions), an unrecognized
  model (must pass), an ARN shape the extraction logic doesn't recognize
  (must pass, not crash), the `skip_dimension_validation` escape hatch, a
  v0.1.0-style configuration (regression), multiple independently-validated
  `kbs` entries, and interaction with PR #10's chunking configuration.
- New optional `expose_ingestion_policy` field (default `false`) on each
  `kbs` entry, and a new `ingestion_policy_documents` output. When set,
  computes (as a plain `jsonencode()` value - no resource, no AWS API call)
  an IAM policy document granting exactly `bedrock:StartIngestionJob`,
  `bedrock:GetIngestionJob`, and `bedrock:ListIngestionJobs`, scoped to that
  KB's own ARN. This module does not create, attach, or otherwise manage
  any IAM resource from this document, and does not add these permissions
  to its own Bedrock execution role - that role is assumed by the Bedrock
  service itself and never calls these actions; they are meant for
  whichever external principal (CI role, application role, Lambda
  execution role, operator role) actually triggers and monitors ingestion.
  See the README's "Bedrock / Ingestion Boundary" section, including why
  the Bedrock execution role was ruled out as a target and why all three
  actions can only be scoped to the knowledge-base ARN (not a specific data
  source), per AWS's own IAM Service Authorization Reference.
- 8 new native `terraform test` cases covering: default (no policy
  produced), opt-in (exact actions/effect/resource asserted), no wildcard
  action or resource, two KBs with independently-scoped policies, one KB
  opted in while a sibling KB is not, a KMS-enabled KB (no extra `kms:*`
  leaks into the ingestion policy), and interaction with PR #10's chunking
  and PR #11's model/dimension validation (neither is affected).

### Changed

- None. `chunking` defaults to `null` (omitted); omitting it sends no
  `vector_ingestion_configuration` at all, so AWS's own default chunking
  behavior (~300 tokens per chunk) is unchanged from v0.1.0. No existing
  input, output, or resource address changes. `skip_dimension_validation`
  defaults to `false`; existing `kbs` entries (v0.1.0 and PR #10) already
  use a known-valid model/dimension pair and are unaffected.
  `expose_ingestion_policy` defaults to `false`; the new
  `ingestion_policy_documents` output is an empty map by default. No IAM
  changes to any existing role or policy.

### Fixed

- `knowledge_base_arns` now uses the actual `awscc_bedrock_knowledge_base`
  attribute (`knowledge_base_arn`) instead of a nonexistent `arn` attribute.
  Every entry previously evaluated to `null` (silently, via `try()`) since
  v0.1.0; entries now return the Knowledge Base's real ARN. Output name, map
  keys, and shape are unchanged - this corrects the existing contract's
  behavior rather than replacing it.

### Known Limitations

- Changing `chunking` on an existing `kbs` entry - including adding it
  where previously omitted - replaces the underlying
  `awscc_bedrock_data_source` resource, per the
  `AWS::Bedrock::DataSource` CloudFormation schema
  (`ChunkingConfiguration` is a `createOnlyProperty`). This module does
  not mask that behavior with `lifecycle { prevent_destroy = true }`; see
  the README's "Chunking" section.
- The embedding model / dimension compatibility map is a maintained
  snapshot, not a live or exhaustive source - see the README's "Embedding
  Model / Dimension Compatibility" section for what's included, what's
  deliberately excluded, and why.
- Changing `chunking` does not itself trigger `StartIngestionJob` -
  ingestion remains outside this module's scope (see "Bedrock / Ingestion
  Boundary" in the README).
- `expose_ingestion_policy`'s resulting policy is scoped to the KB's ARN,
  not to a specific data source - AWS's IAM Service Authorization Reference
  does not expose resource-level scoping finer than `knowledge-base` for
  `StartIngestionJob`/`GetIngestionJob`/`ListIngestionJobs`. This module
  currently creates one data source per KB, so this has no practical effect
  today, but a principal granted this policy could start/monitor ingestion
  for any data source under that KB if more than one ever existed.

## [0.1.0] - 2026-08-28

Initial public release.

### Added

- Amazon Bedrock Knowledge Base provisioning via a single `kbs` map input,
  supporting multiple Knowledge Base definitions in one apply.
- Amazon S3 Vectors as the vector store: create a managed vector bucket +
  index, or reference an existing S3 Vectors index by ARN.
- A dedicated S3 bucket per Knowledge Base for source documents, with:
  - Versioning enabled
  - S3 Block Public Access enforced
  - TLS-only access enforced via a bucket policy
  - Incomplete multipart upload cleanup (always on)
  - Optional noncurrent-version retention (opt-in via
    `noncurrent_version_expiration_days`)
  - Optional SSE-KMS encryption, bring your own key (`kms_key_arn`)
  - Optional S3 server access logging to an existing external bucket
    (`logging_target_bucket`)
- Scoped IAM role and least-privilege policies for the Bedrock execution
  role (invoke embedding model, read S3 documents, S3 Vectors index
  access, optional KMS access).
- A native `terraform test` suite (mock-provider based, no AWS credentials
  required) covering both S3 Vectors modes, input validation, and docs
  bucket hardening.
- CI: `terraform fmt`, `validate`, `terraform test`, `tflint`, `checkov`
  (targeted policy), and a `terraform-docs` drift check.
- `LICENSE` (MIT), `CONTRIBUTING.md`, and generated
  Requirements/Providers/Resources/Inputs/Outputs documentation.

### Changed

- The `Module` tag value applied to every resource this module creates
  was changed from `matrix-vector-nexus` to `bedrock-vector-kb` to match
  the module's public identity. This updates tags in place on any
  already-applied resources; it does not change any resource address and
  does not force replacement.
- The reusable module moved to the repository root (previously under
  `modules/matrix-vector-nexus/`), so the repository itself is the
  consumable module.

### Removed

- Three input variables that never had any effect on any resource were
  removed before this first release, rather than published as permanent
  no-ops: `kb_prefix`, `account_id`, and `enable_bedrock_data_automation`.
  None had internal usage or a committed roadmap; since no prior tagged
  release exists, this is pre-release API cleanup, not a breaking change.

### Security

- S3 documents bucket: Block Public Access, TLS-only bucket policy,
  versioning, encryption at rest (SSE-S3 by default, optional SSE-KMS).
- IAM least privilege: every policy is scoped to the specific resource it
  needs (embedding model ARN, content bucket/prefix, S3 Vectors index ARN,
  optional KMS key ARN) - no wildcard actions or resources.

### Known Limitations

- No automatic document ingestion/sync: provisioning the S3 data source
  does not trigger Bedrock ingestion; `StartIngestionJob` must be run
  separately (console, CLI, or SDK).
- No chunking strategy configuration, embedding-model/dimension
  validation, guardrails, or observability wiring.
- Cross-region replication and S3 event notifications are not
  implemented (no disaster-recovery contract or event consumer exists in
  this module).
