#!/usr/bin/env python3
"""Generate synthetic clinic records for local sandbox testing."""

from __future__ import annotations

import argparse
import json
import random
from datetime import date, timedelta
from pathlib import Path

FIRST_NAMES = [
    "Alex",
    "Jordan",
    "Sam",
    "Taylor",
    "Casey",
    "Morgan",
    "Drew",
    "Riley",
    "Robin",
    "Avery",
]

LAST_NAMES = [
    "Rivera",
    "Patel",
    "Nguyen",
    "Johnson",
    "Smith",
    "Lee",
    "Garcia",
    "Lopez",
    "Baker",
    "Kim",
]

THERAPISTS = [
    "Dr. Elena Mendez",
    "Dr. Nikhil Shah",
    "Dr. Grace Hopkins",
    "Dr. Luis Ocampo",
]

DIAGNOSES = [
    "Low back pain",
    "Rotator cuff strain",
    "Knee osteoarthritis",
    "Post-op ACL rehabilitation",
    "Cervical radiculopathy",
]

PLAN_TEMPLATES = [
    "Manual therapy + home exercise program",
    "Strength progression + gait retraining",
    "Mobility work + pain modulation protocol",
    "Neuromuscular re-education + balance drills",
]


def random_birthdate(min_age: int = 18, max_age: int = 85) -> str:
    today = date.today()
    age = random.randint(min_age, max_age)
    day_offset = random.randint(0, 364)
    dob = today - timedelta(days=(age * 365 + day_offset))
    return dob.isoformat()


def create_patient(patient_id: int) -> dict:
    first = random.choice(FIRST_NAMES)
    last = random.choice(LAST_NAMES)
    encounter_days_ago = random.randint(1, 120)
    encounter_date = date.today() - timedelta(days=encounter_days_ago)

    return {
        "patient_id": f"LC-{patient_id:04d}",
        "name": {
            "first": first,
            "last": last,
        },
        "birth_date": random_birthdate(),
        "sex": random.choice(["female", "male", "other", "unknown"]),
        "phone": f"+1-555-01{random.randint(10, 99)}",
        "encounter": {
            "date": encounter_date.isoformat(),
            "therapist": random.choice(THERAPISTS),
            "diagnosis": random.choice(DIAGNOSES),
            "pain_score": random.randint(1, 10),
            "rom_observation": random.choice(
                [
                    "Limited shoulder abduction to 90 degrees",
                    "Lumbar flexion reduced by 30%",
                    "Knee extension lag of 8 degrees",
                    "Cervical rotation painful at end range",
                ]
            ),
            "plan": random.choice(PLAN_TEMPLATES),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="./data", help="Output directory")
    parser.add_argument("--count", type=int, default=20, help="Number of mock patients")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for repeatable output")
    args = parser.parse_args()

    random.seed(args.seed)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    dataset = {
        "clinic": "Lean Clinic Sandbox",
        "generated_on": date.today().isoformat(),
        "patients": [create_patient(i) for i in range(1, args.count + 1)],
    }

    output_file = out_dir / "mock_clinic_data.json"
    output_file.write_text(json.dumps(dataset, indent=2), encoding="utf-8")
    print(f"Wrote synthetic data to {output_file}")


if __name__ == "__main__":
    main()
