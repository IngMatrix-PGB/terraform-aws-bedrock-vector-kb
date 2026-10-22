# Acme Platform - AWS Access

*Fictional sample document for the RAG demo.*

## How engineers get access

- All human access goes through AWS IAM Identity Center (SSO). IAM users
  with long-lived access keys are not allowed.
- Read-only access to non-production accounts is granted automatically to
  every engineer.
- Production access is temporary: request it in the access portal, a team
  lead approves it, and it expires after 4 hours.

## Workloads

- Kubernetes workloads use IRSA (IAM Roles for Service Accounts); static
  credentials in pods are forbidden.
- CI pipelines authenticate to AWS with GitHub Actions OIDC, never with
  stored secrets.

## Break-glass

A break-glass role exists for when SSO is down. Using it pages the security
team immediately, and every use is reviewed within 24 hours.
