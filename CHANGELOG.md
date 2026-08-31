# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
