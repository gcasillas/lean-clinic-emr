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
- Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)

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
./phase3-cloud-deployment/rotate_db_secrets.sh --config .env
```

This script manages:

- `SECRET_DB_USER`
- `SECRET_DB_PASS`
- `SECRET_DB_ROOT_PASS`

## OpenEMR installer gotcha

The OpenEMR web installer cannot reliably use `/cloudsql/<connection-name>` as host in setup forms.
If the installer step needs DB connectivity, use temporary TCP host (Cloud SQL public IP) for installer entry only.

When `MANUAL_SETUP=yes`, the Cloud Run service can be healthy while `/apis/default/api/` returns HTTP 500 until installer steps are completed. This is expected pre-install behavior and does not necessarily indicate a failed deployment.

## Post-install security checklist

1. Remove temporary broad authorized networks (`0.0.0.0/0`).
2. Keep Cloud Run service connected through Cloud SQL connector + Secret Manager IAM.
3. Restrict SQL authorized networks to connector-only or explicit admin CIDRs.
4. Verify `MANUAL_SETUP` mode is correct for your stage.
5. Run smoke checks:

```bash
./phase3-cloud-deployment/smoke_test_deployment.sh --config .env
```

## Persist OpenEMR sqlconf.php Across Revisions

Recommended one-pass command:

```bash
./phase3-cloud-deployment/lock_openemr_runtime.sh --config .env
```

This configures Cloud SQL Proxy sidecar + persisted `sqlconf.php` and hardens SQL network access in one workflow.

Manual path (advanced):

Cloud Run revisions are immutable and may not preserve installer-generated files between rollouts.
To avoid setup reappearing after updates, store `sites/default/sqlconf.php` in Secret Manager and mount it as a runtime file.

```bash
./phase3-cloud-deployment/upsert_openemr_sqlconf_secret.sh --config .env
```

Then set `USE_SQLCONF_SECRET_MOUNT=yes` in `.env` and run:

```bash
./phase3-cloud-deployment/configure_cloud_emr.sh --config .env --manual-setup yes
```

## Optional PACS/DICOM readiness

If you want infrastructure ready for future PACS integration without deploying PACS today:

```bash
./phase2-cloud-push/init_gcp_dicom_store.sh --config .env
```

This creates Healthcare API DICOM dataset/store resources only.

## Manual secret example (if needed)

```bash
echo -n "openemr" | gcloud secrets create openemr-db-user --data-file=-
echo -n "strong-db-password" | gcloud secrets create openemr-db-pass --data-file=-
echo -n "strong-root-password" | gcloud secrets create openemr-db-root-pass --data-file=-
```
