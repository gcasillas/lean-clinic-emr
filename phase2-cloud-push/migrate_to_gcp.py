#!/usr/bin/env python3
"""Upload a local FHIR bundle to Google Cloud Healthcare API using gcloud auth."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


def get_access_token() -> str:
    cmd = ["gcloud", "auth", "print-access-token"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("Failed to get access token from gcloud")
    return token


def build_bundle_endpoint(project: str, region: str, dataset: str, fhir_store: str) -> str:
    return (
        "https://healthcare.googleapis.com/v1/projects/"
        f"{project}/locations/{region}/datasets/{dataset}/fhirStores/{fhir_store}/fhir"
    )


def upload_bundle(bundle_path: Path, endpoint: str, token: str) -> None:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    payload = json.dumps(bundle).encode("utf-8")

    request = urllib.request.Request(
        url=endpoint,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/fhir+json; charset=utf-8",
            "Accept": "application/fhir+json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read().decode("utf-8")
            status = response.getcode()
            print(f"Upload completed with HTTP {status}")
            if body:
                print(body[:2000])
    except urllib.error.HTTPError as err:
        details = err.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Upload failed with HTTP {err.code}: {details}") from err


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ[key] = value


def resolve_value(cli_value: str | None, *env_keys: str) -> str | None:
    if cli_value:
        return cli_value
    for env_key in env_keys:
        value = os.getenv(env_key)
        if value:
            return value
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=".env", help="Path to root config env file")
    parser.add_argument("--profile", help="Profile name to load from profiles/<name>.env")
    parser.add_argument("--project")
    parser.add_argument("--region")
    parser.add_argument("--dataset")
    parser.add_argument("--fhir-store")
    parser.add_argument("--bundle", help="Path to local FHIR transaction bundle")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    root_dir = script_dir.parent
    if args.profile:
        load_env_file(root_dir / "profiles" / f"{args.profile}.env")
    load_env_file((root_dir / args.config).resolve() if not Path(args.config).is_absolute() else Path(args.config))

    project = resolve_value(args.project, "PROJECT_ID")
    region = resolve_value(args.region, "REGION")
    dataset = resolve_value(args.dataset, "DATASET_ID")
    fhir_store = resolve_value(args.fhir_store, "FHIR_STORE_ID")
    bundle = resolve_value(args.bundle, "BUNDLE_PATH")

    missing = [
        name
        for name, value in {
            "project": project,
            "region": region,
            "dataset": dataset,
            "fhir-store": fhir_store,
            "bundle": bundle,
        }.items()
        if not value
    ]
    if missing:
        print(
            "Missing required values: "
            + ", ".join(missing)
            + ". Use CLI flags or set PROJECT_ID, REGION, DATASET_ID, FHIR_STORE_ID, and BUNDLE_PATH in config.",
            file=sys.stderr,
        )
        sys.exit(1)

    bundle_path = Path(bundle)
    if not bundle_path.exists():
        print(f"Bundle not found: {bundle_path}", file=sys.stderr)
        sys.exit(1)

    try:
        token = get_access_token()
        endpoint = build_bundle_endpoint(project, region, dataset, fhir_store)
        upload_bundle(bundle_path, endpoint, token)
    except (subprocess.CalledProcessError, RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
