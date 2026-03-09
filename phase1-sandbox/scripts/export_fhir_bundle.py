#!/usr/bin/env python3
"""Transform synthetic clinic JSON into a minimal FHIR transaction bundle."""

from __future__ import annotations

import argparse
import json
import uuid
from pathlib import Path

SEX_TO_FHIR = {
    "female": "female",
    "male": "male",
    "other": "other",
    "unknown": "unknown",
}


def patient_resource(patient: dict) -> dict:
    return {
        "resourceType": "Patient",
        "id": patient["patient_id"],
        "identifier": [
            {
                "system": "https://clinic.local/patient-id",
                "value": patient["patient_id"],
            }
        ],
        "name": [
            {
                "family": patient["name"]["last"],
                "given": [patient["name"]["first"]],
            }
        ],
        "telecom": [{"system": "phone", "value": patient["phone"], "use": "mobile"}],
        "gender": SEX_TO_FHIR.get(patient["sex"], "unknown"),
        "birthDate": patient["birth_date"],
    }


def encounter_resource(patient: dict) -> dict:
    encounter_id = str(uuid.uuid4())
    return {
        "resourceType": "Encounter",
        "id": encounter_id,
        "status": "finished",
        "class": {
            "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
            "code": "AMB",
            "display": "ambulatory",
        },
        "subject": {"reference": f"Patient/{patient['patient_id']}"},
        "period": {"start": patient["encounter"]["date"], "end": patient["encounter"]["date"]},
        "reasonCode": [{"text": patient["encounter"]["diagnosis"]}],
    }


def observation_resource(patient: dict) -> dict:
    obs_id = str(uuid.uuid4())
    return {
        "resourceType": "Observation",
        "id": obs_id,
        "status": "final",
        "code": {"text": "Pain score"},
        "subject": {"reference": f"Patient/{patient['patient_id']}"},
        "effectiveDateTime": patient["encounter"]["date"],
        "valueInteger": patient["encounter"]["pain_score"],
        "note": [{"text": patient["encounter"]["rom_observation"]}],
    }


def careplan_resource(patient: dict) -> dict:
    careplan_id = str(uuid.uuid4())
    return {
        "resourceType": "CarePlan",
        "id": careplan_id,
        "status": "active",
        "intent": "plan",
        "subject": {"reference": f"Patient/{patient['patient_id']}"},
        "description": patient["encounter"]["plan"],
        "title": "Physical therapy treatment plan",
    }


def to_bundle(dataset: dict) -> dict:
    entries = []
    for patient in dataset["patients"]:
        resources = [
            patient_resource(patient),
            encounter_resource(patient),
            observation_resource(patient),
            careplan_resource(patient),
        ]
        for resource in resources:
            entries.append(
                {
                    "fullUrl": f"urn:uuid:{resource['id']}",
                    "resource": resource,
                    "request": {
                        "method": "PUT",
                        "url": f"{resource['resourceType']}/{resource['id']}",
                    },
                }
            )

    return {
        "resourceType": "Bundle",
        "type": "transaction",
        "entry": entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Path to synthetic clinic JSON")
    parser.add_argument("--output", required=True, help="Path to output FHIR bundle")
    args = parser.parse_args()

    source = Path(args.input)
    destination = Path(args.output)

    dataset = json.loads(source.read_text(encoding="utf-8"))
    bundle = to_bundle(dataset)

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(bundle, indent=2), encoding="utf-8")
    print(f"Wrote FHIR bundle with {len(bundle['entry'])} entries to {destination}")


if __name__ == "__main__":
    main()
