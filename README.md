# Lean Clinic EMR Starter Kit

Reusable OpenEMR starter kit for cloud-first clinics with profile-driven deployment,
FHIR interoperability, and security hardening built into the workflow.

## Core principles

- Security first: no plaintext secrets in repo config or docs.
- Reusability: scripts are generic and driven by profile + env config.
- Separation of concerns: core platform automation is separate from clinic profile defaults.
- Fast validation: smoke checks catch Cloud SQL/Cloud Run setup drift early.

## Repository structure

```text
.
├── .env.example                    # Single config template for new deployments
├── config.template                 # Alternate copy of root config template
├── profiles/
│   ├── primary-care.env
│   └── holistic-herbal.env
├── scripts/
│   ├── bootstrap_new_clinic_deployment.sh
│   └── lib/config.sh
├── phase1-sandbox/
├── phase2-cloud-push/
└── phase3-cloud-deployment/
```

## Quick start for a new clinic

1. Create config and choose a profile.

```bash
cp .env.example .env
# Set CLINIC_PROFILE=primary-care or CLINIC_PROFILE=holistic-herbal
```

2. Run one bootstrap command.

```bash
./scripts/bootstrap_new_clinic_deployment.sh --config .env --profile holistic-herbal
```

3. Complete OpenEMR web installer, then harden SQL networking.

```bash
./phase3-cloud-deployment/harden_cloud_sql_network.sh --config .env --profile holistic-herbal
```

## Security hardening workflow

1. Rotate DB credentials in Secret Manager.

```bash
./phase3-cloud-deployment/rotate_db_secrets.sh --config .env --profile holistic-herbal
```

2. Provision Cloud SQL with Secret Manager-backed DB user credentials.

```bash
./phase3-cloud-deployment/setup_cloud_sql.sh --config .env --profile holistic-herbal
```

3. Deploy Cloud Run without plaintext DB credentials.

```bash
./phase3-cloud-deployment/deploy_to_cloud_run.sh --config .env --profile holistic-herbal
./phase3-cloud-deployment/configure_cloud_emr.sh --config .env --profile holistic-herbal
```

4. Remove temporary SQL open network (`0.0.0.0/0`) once installer access is complete.

```bash
./phase3-cloud-deployment/harden_cloud_sql_network.sh --config .env --profile holistic-herbal
```

## OpenEMR installer runbook note

OpenEMR installer setup cannot reliably use `/cloudsql/...` as DB host in the web setup form.
For installer screens, use a TCP host (Cloud SQL public IP) temporarily if needed.
After setup succeeds, immediately remove broad SQL network access and keep Cloud Run + connector wiring in place.

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
./init_gcp_fhir_store.sh --config ../.env --profile holistic-herbal
python3 migrate_to_gcp.py --config ../.env --profile holistic-herbal
./validate_migration.sh --config ../.env --profile holistic-herbal
```

### Phase 3: Cloud deployment checks

```bash
cd phase3-cloud-deployment
./smoke_test_deployment.sh --config ../.env --profile holistic-herbal
```

## Safety and data handling

- Use synthetic/test records in sandbox and migration demos.
- Do not commit PHI.
- Keep all credentials in Secret Manager.
- Keep `.env` free of secret values.
