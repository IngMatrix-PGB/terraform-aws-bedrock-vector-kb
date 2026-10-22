# Acme Platform - Deployment Policy

*Fictional sample document for the RAG demo.*

## Deployment windows

- Production deployments run Monday to Thursday, 09:00-17:00 UTC.
- On Fridays, production deployments are frozen after 14:00 UTC.
- No production deployments on public holidays or during the year-end
  freeze (December 20 to January 3).
- Emergency fixes outside these windows need approval from the on-call
  Incident Commander and must be linked to an open incident.

## Requirements before deploying to production

1. The change has been running in staging for at least 24 hours.
2. All CI checks passed, including the container image scan (no CRITICAL
   vulnerabilities).
3. The pull request has at least one approval from a code owner.
4. A rollback plan is written in the pull request description.

## Rollback

Every service deploys through Argo CD. To roll back, revert the commit in
the GitOps repository; Argo CD syncs the previous version within 3 minutes.
Database migrations must be backward compatible for one release, so a
rollback never requires a manual schema change.
