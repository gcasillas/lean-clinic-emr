# Google Cloud Guide

## Security policy

- Zero plaintext credentials in repository files and docs.
- Store DB user/password/root password only in Secret Manager.
- Use Secret Manager references in Cloud Run (`--set-secrets`) instead of inline env values.

## Required APIs

- Cloud Healthcare API (`healthcare.googleapis.com`)
- Cloud SQL Admin API (`sqladmin.googleapis.com`)
- Cloud Run Admin API (`run.googleapis.com`)
- Secret Manager API (`secretmanager.googleapis.com`)

## Minimal IAM suggestions

- FHIR migration operator:
  - `roles/healthcare.datasetAdmin`
  - `roles/healthcare.fhirResourceEditor`
- Deployment operator:
  - `roles/run.admin`
  - `roles/cloudsql.admin`
  - `roles/secretmanager.admin`
  - `roles/iam.serviceAccountUser`

## Secret setup and rotation

Use the included rotation script to create/update secrets and add new versions:

```bash
./phase3-cloud-deployment/rotate_db_secrets.sh --config .env --profile holistic-herbal
```

This script manages:

- `SECRET_DB_USER`
- `SECRET_DB_PASS`
- `SECRET_DB_ROOT_PASS`

## OpenEMR installer gotcha

The OpenEMR web installer cannot reliably use `/cloudsql/<connection-name>` as host in setup forms.
If the installer step needs DB connectivity, use temporary TCP host (Cloud SQL public IP) for installer entry only.

## Post-install security checklist

1. Remove temporary broad authorized networks (`0.0.0.0/0`).
2. Keep Cloud Run service connected through Cloud SQL connector + Secret Manager IAM.
3. Restrict SQL authorized networks to connector-only or explicit admin CIDRs.
4. Verify `MANUAL_SETUP` mode is correct for your stage.
5. Run smoke checks:

```bash
./phase3-cloud-deployment/smoke_test_deployment.sh --config .env --profile holistic-herbal
```

## Manual secret example (if needed)

```bash
echo -n "openemr" | gcloud secrets create openemr-db-user --data-file=-
echo -n "strong-db-password" | gcloud secrets create openemr-db-pass --data-file=-
echo -n "strong-root-password" | gcloud secrets create openemr-db-root-pass --data-file=-
```
