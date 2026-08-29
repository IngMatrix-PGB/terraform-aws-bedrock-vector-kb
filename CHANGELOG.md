# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
