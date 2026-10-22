# Acme Platform - Incident Response

*Fictional sample document for the RAG demo.*

## Severity levels

| Severity | Definition | First response |
|---|---|---|
| SEV1 | Customer-facing outage or data loss | Page on-call within 5 minutes, status page update within 15 minutes |
| SEV2 | Degraded service, workaround exists | Acknowledge within 15 minutes |
| SEV3 | Internal impact only | Next business day |

## Roles

- **Incident Commander (IC):** owns decisions and communication. The
  on-call SRE is IC by default until they hand off.
- **Communications lead:** posts updates in #incidents every 30 minutes
  during a SEV1.
- **Subject matter experts:** join when the IC pages them.

## After the incident

A blameless postmortem is required for every SEV1 and SEV2, published
within 5 business days. It lists the timeline, root cause, what went well,
and action items, each with an owner and a due date.
