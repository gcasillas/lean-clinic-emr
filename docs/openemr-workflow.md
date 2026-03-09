# OpenEMR Workflow (Lean Clinic)

## Clinical scope

- New patient intake
- Physiotherapy assessment notes
- Range-of-motion observations
- Treatment plan and follow-up encounters

## Recommended local process

1. Start local stack with `docker compose up -d`.
2. Log into OpenEMR and create template forms for rehab sessions.
3. Generate synthetic patient and encounter data for testing.
4. Export to FHIR bundle and run migration scripts.

## Cloud installer runbook notes

- If using OpenEMR setup in Cloud Run, the installer form should use a TCP DB host value for setup connectivity (for example, temporary Cloud SQL public IP).
- Do not enter `/cloudsql/<instance-connection-name>` in the OpenEMR setup web form host field.
- After installer completion, remove temporary open SQL network rules and keep connector/IAM-based access paths.

## Post-install checks

1. Confirm Cloud SQL network rules do not include `0.0.0.0/0`.
2. Confirm Cloud Run revision is ready.
3. Confirm DB credentials are sourced from Secret Manager only.
4. Run `phase3-cloud-deployment/smoke_test_deployment.sh`.

## Example role mapping

- Therapist: creates encounter notes and care plans
- Front desk: patient registration and schedule handling
- Admin: data export and cloud migration operations
