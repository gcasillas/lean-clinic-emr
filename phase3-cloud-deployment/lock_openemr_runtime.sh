#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  lock_openemr_runtime.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>] [--instance <SQL_INSTANCE>]

Optional:
  --secret-sqlconf <SECRET_NAME>
  --manual-setup <yes|no>
  --skip-harden-sql

One-pass runtime lock-in:
  1) Upsert sqlconf.php secret for localhost DB host (127.0.0.1)
  2) Deploy Cloud Run with Cloud SQL Proxy sidecar + deterministic startup wrapper
  3) Optionally harden Cloud SQL network (remove 0.0.0.0/0)
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
SERVICE="${SERVICE_NAME:-}"
INSTANCE="${SQL_INSTANCE:-}"
DATABASE="${MYSQL_DATABASE:-openemr}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF:-openemr-sqlconf}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP:-yes}"
HARDEN_SQL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --mysql-port) MYSQL_PORT_VAL="$2"; shift 2 ;;
    --secret-sqlconf) SECRET_SQLCONF_NAME="$2"; shift 2 ;;
    --manual-setup) MANUAL_SETUP_VALUE="$2"; shift 2 ;;
    --skip-harden-sql) HARDEN_SQL=false; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
SERVICE="${SERVICE:-${SERVICE_NAME:-}}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF_NAME:-${SECRET_SQLCONF:-openemr-sqlconf}}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP_VALUE:-${MANUAL_SETUP:-yes}}"

require_var PROJECT
require_var REGION
require_var SERVICE
require_var INSTANCE
require_var SECRET_SQLCONF_NAME

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com cloudresourcemanager.googleapis.com >/dev/null

SERVICE_ACCOUNT_VALUE="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(spec.template.spec.serviceAccountName)')"
if [[ -z "$SERVICE_ACCOUNT_VALUE" ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  SERVICE_ACCOUNT_VALUE="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi

CONNECTION_NAME="$(gcloud sql instances describe "$INSTANCE" --format='value(connectionName)')"
if [[ -z "$CONNECTION_NAME" ]]; then
  echo "Unable to resolve Cloud SQL connection name for instance: $INSTANCE" >&2
  exit 1
fi

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SERVICE_ACCOUNT_VALUE}" \
  --role="roles/cloudsql.client" \
  --quiet >/dev/null

"${SCRIPT_DIR}/upsert_openemr_sqlconf_secret.sh" \
  --config "$CONFIG_FILE" \
  --project "$PROJECT" \
  --instance "$INSTANCE" \
  --database "$DATABASE" \
  --mysql-port "$MYSQL_PORT_VAL" \
  --mysql-host 127.0.0.1 \
  --secret-sqlconf "$SECRET_SQLCONF_NAME"

gcloud secrets add-iam-policy-binding "$SECRET_SQLCONF_NAME" \
  --member="serviceAccount:${SERVICE_ACCOUNT_VALUE}" \
  --role="roles/secretmanager.secretAccessor" \
  >/dev/null

SERVICE_EXPORT="$(mktemp /tmp/openemr-service-XXXX.yaml)"
gcloud run services describe "$SERVICE" --region "$REGION" --format export > "$SERVICE_EXPORT"

STARTUP_WRAPPER="mkdir -p /var/www/localhost/htdocs/openemr/sites/default/documents/logs_and_misc/methods && chmod -R 777 /var/www/localhost/htdocs/openemr/sites/default/documents && if [ -f /tmp/sqlconf.php ]; then cp /tmp/sqlconf.php /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php; chmod 644 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php; fi && exec ./openemr.sh"
export SERVICE_EXPORT CONNECTION_NAME MYSQL_PORT_VAL DATABASE MANUAL_SETUP_VALUE STARTUP_WRAPPER SECRET_SQLCONF_NAME
python3 - <<'PY'
import os
import time
import yaml

path = os.environ["SERVICE_EXPORT"]
connection_name = os.environ["CONNECTION_NAME"]
mysql_port = str(os.environ["MYSQL_PORT_VAL"])
database = os.environ["DATABASE"]
manual_setup = os.environ["MANUAL_SETUP_VALUE"]
startup_wrapper = os.environ["STARTUP_WRAPPER"]
secret_sqlconf = os.environ["SECRET_SQLCONF_NAME"]

with open(path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

spec = data["spec"]["template"]["spec"]
containers = spec.get("containers", [])
if not containers:
    raise RuntimeError("No containers found in Cloud Run service spec")

app = containers[0]
app["name"] = "openemr"
app["command"] = ["/bin/sh"]
app["args"] = ["-c", startup_wrapper]

env = app.setdefault("env", [])
env_map = {e.get("name"): e for e in env if isinstance(e, dict) and e.get("name")}
for key, value in {
    "OE_MODE": "prod",
    "MANUAL_SETUP": str(manual_setup),
    "MYSQL_HOST": "127.0.0.1",
    "MYSQL_PORT": mysql_port,
    "MYSQL_DATABASE": database,
    "SQLCONF_SECRET_VERSION": str(int(time.time())),
}.items():
    if key in env_map:
        env_map[key]["value"] = value
        env_map[key].pop("valueFrom", None)
    else:
        env.append({"name": key, "value": value})

if not app.get("ports"):
    app["ports"] = [{"containerPort": 80, "name": "http1"}]

mounts = app.setdefault("volumeMounts", [])
mount_map = {m.get("name"): m for m in mounts if isinstance(m, dict) and m.get("name")}
if "openemr-docs" not in mount_map:
    mounts.append({"name": "openemr-docs", "mountPath": "/var/www/localhost/htdocs/openemr/sites/default/documents"})
if "openemr-sqlconf-sox-vol" not in mount_map:
    mounts.append({"name": "openemr-sqlconf-sox-vol", "mountPath": "/tmp"})

proxy_idx = next((i for i, c in enumerate(containers) if c.get("name") == "cloud-sql-proxy"), None)
proxy = {
    "name": "cloud-sql-proxy",
    "image": "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4",
    "args": ["--structured-logs", "--address=0.0.0.0", "--port=3306", connection_name],
    "resources": {"limits": {"cpu": "250m", "memory": "256Mi"}},
}
if proxy_idx is None:
    containers.append(proxy)
else:
    containers[proxy_idx] = proxy

spec["containers"] = containers
spec["serviceAccountName"] = spec.get("serviceAccountName")

volumes = spec.setdefault("volumes", [])
vol_map = {v.get("name"): v for v in volumes if isinstance(v, dict) and v.get("name")}
vol_map["openemr-docs"] = {
    "name": "openemr-docs",
    "emptyDir": {"medium": "Memory", "sizeLimit": "512Mi"},
}
vol_map["openemr-sqlconf-sox-vol"] = {
    "name": "openemr-sqlconf-sox-vol",
    "secret": {
        "secretName": secret_sqlconf,
        "items": [{"key": "latest", "path": "sqlconf.php"}],
    },
}
spec["volumes"] = list(vol_map.values())

ann = data["spec"]["template"].setdefault("metadata", {}).setdefault("annotations", {})
ann["run.googleapis.com/cloudsql-instances"] = connection_name

with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY

gcloud run services replace "$SERVICE_EXPORT" --region "$REGION" >/dev/null

if [[ "$HARDEN_SQL" == true ]]; then
  "${SCRIPT_DIR}/harden_cloud_sql_network.sh" --config "$CONFIG_FILE" --project "$PROJECT" --instance "$INSTANCE"
fi

SERVICE_URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
LOGIN_CODE="$(curl -sS -o /dev/null -w "%{http_code}" "${SERVICE_URL}/interface/login/login.php?site=default")"

echo "Runtime lock complete."
echo "Service URL: ${SERVICE_URL}"
echo "Login endpoint status: ${LOGIN_CODE}"
if [[ "$HARDEN_SQL" == true ]]; then
  echo "Cloud SQL network hardening: applied"
else
  echo "Cloud SQL network hardening: skipped (--skip-harden-sql)"
fi
