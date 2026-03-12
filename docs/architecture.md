# Lean Clinic EMR Architecture

## Design goals

- Keep EMR onboarding independent from PACS/DICOM concerns
- Make local-to-cloud migration reproducible with scripts
- Use standards-based data exchange through FHIR R4

## Logical flow

1. OpenEMR runs locally in Docker for sandbox workflows.
2. Synthetic records are exported to a FHIR transaction bundle.
3. Bundle is sent to Cloud Healthcare API FHIR store.
4. OpenEMR is deployed to Cloud Run with Cloud SQL (MySQL) backend.

## Components

- `phase1-sandbox/`: local OpenEMR + synthetic data generation
- `phase2-cloud-push/`: FHIR store creation and migration validation
- `phase3-cloud-deployment/`: Cloud SQL + Cloud Run operational scripts
- `scripts/`: bootstrap and shared config loader
- `integration/`: reserved bridge patterns for future PACS or AI services

## Deployment model

- Single clinic baseline:
One generic clinic config drives resource names, deployment settings, and OpenEMR runtime defaults.

- FHIR now:
FHIR store provisioning and migration are first-class and deployed as part of the main workflow.

- PACS/DICOM ready:
DICOM dataset/store can be pre-created on demand, while PACS app deployment remains out of scope for now.

## Security baseline

- Use synthetic test data in development
- Keep credentials in Secret Manager, not committed to git
- Restrict service-account IAM to minimum roles required
