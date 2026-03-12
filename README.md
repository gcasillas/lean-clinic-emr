# Lean Clinic EMR Starter Kit

Reusable OpenEMR starter kit for cloud-first clinics with a single generic deployment model,
FHIR interoperability, and security hardening built into the workflow.

## Core principles

- Security first: no plaintext secrets in repo config or docs.
- Reusability: scripts are generic and driven by one clinic config.
- Separation of concerns: core platform automation is separate from clinic-specific content customization.
- Fast validation: smoke checks catch Cloud SQL/Cloud Run setup drift early.
- Progressive imaging support: PACS/DICOM resources can be prepared on demand without changing the FHIR-first path.

## Repository structure

```text
.
├── .env.example                    # Single config template for new deployments
├── config.template                 # Alternate copy of root config template
├── scripts/
│   ├── bootstrap_new_clinic_deployment.sh
│   └── lib/config.sh
├── phase1-sandbox/
├── phase2-cloud-push/
└── phase3-cloud-deployment/
```

## Quick start for a new clinic

1. Create config.

```bash
cp .env.example .env
```

2. Run one bootstrap command (FHIR deploy path).

```bash
./scripts/bootstrap_new_clinic_deployment.sh --config .env
```

3. Optional: pre-create DICOM resources for PACS readiness (no PACS app deployment).

```bash
./phase2-cloud-push/init_gcp_dicom_store.sh --config .env
```

4. Complete OpenEMR web installer, then harden SQL networking.

```bash
./phase3-cloud-deployment/harden_cloud_sql_network.sh --config .env
```

## Security hardening workflow

1. Rotate DB credentials in Secret Manager.

```bash
./phase3-cloud-deployment/rotate_db_secrets.sh --config .env
```

2. Provision Cloud SQL with Secret Manager-backed DB user credentials.

```bash
./phase3-cloud-deployment/setup_cloud_sql.sh --config .env
```

3. Deploy Cloud Run without plaintext DB credentials.

```bash
./phase3-cloud-deployment/deploy_to_cloud_run.sh --config .env
./phase3-cloud-deployment/configure_cloud_emr.sh --config .env
```

4. Remove temporary SQL open network (`0.0.0.0/0`) once installer access is complete.

```bash
./phase3-cloud-deployment/harden_cloud_sql_network.sh --config .env
```

## OpenEMR installer runbook note

OpenEMR installer setup cannot reliably use `/cloudsql/...` as DB host in the web setup form.
For installer screens, use a TCP host (Cloud SQL public IP) temporarily if needed.
After setup succeeds, immediately remove broad SQL network access and keep Cloud Run + connector wiring in place.

When `MANUAL_SETUP=yes`, the service can be healthy while `/apis/default/api/` still returns HTTP 500 until installer steps are completed. This is expected pre-install behavior and does not necessarily indicate a failed Cloud Run deployment.

## Lock Install State Across Revisions

Use the one-pass runtime lock script after you complete installer once.

```bash
./phase3-cloud-deployment/lock_openemr_runtime.sh --config .env
```

Or with Make:

```bash
make lock-runtime CONFIG=.env
```

This command will:

1. Upsert `SECRET_SQLCONF` with localhost DB host (`127.0.0.1`).
2. Deploy Cloud Run with a `cloud-sql-proxy` sidecar.
3. Persist and copy `sqlconf.php` at startup.
4. Remove temporary SQL public network access (`0.0.0.0/0`).

Manual fallback (advanced):

To prevent re-entering setup after Cloud Run creates a new revision, persist `sites/default/sqlconf.php` in Secret Manager and mount it as a file at runtime.

1. Create or update `SECRET_SQLCONF` from current DB secret values.

```bash
./phase3-cloud-deployment/upsert_openemr_sqlconf_secret.sh --config .env
```

2. Enable secret file mount in `.env`.

```bash
USE_SQLCONF_SECRET_MOUNT=yes
SQLCONF_MOUNT_PATH=/tmp/sqlconf.php
```

3. Reconfigure Cloud Run.

```bash
./phase3-cloud-deployment/configure_cloud_emr.sh --config .env --manual-setup yes
```

This keeps DB connection config stable across revisions without storing plaintext credentials in repo files.

## Phase commands (advanced/manual)

### Phase 1: Local sandbox

```bash
cp phase1-sandbox/.env.example phase1-sandbox/.env
cd phase1-sandbox && docker compose up -d
python3 scripts/generate_mock_data.py --out-dir ./data
python3 scripts/export_fhir_bundle.py --input ./data/mock_clinic_data.json --output ./data/fhir_bundle.json
```

### Phase 2: FHIR push

```bash
cd phase2-cloud-push
./init_gcp_fhir_store.sh --config ../.env
python3 migrate_to_gcp.py --config ../.env
./validate_migration.sh --config ../.env
```

### Phase 3: Cloud deployment checks

```bash
cd phase3-cloud-deployment
./smoke_test_deployment.sh --config ../.env
```

## Safety and data handling

- Use synthetic/test records in sandbox and migration demos.
- Do not commit PHI.
- Keep all credentials in Secret Manager.
- Keep `.env` free of secret values.
