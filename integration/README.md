# Future Integration Notes

This repository remains EMR-first by design.

Integration code should stay profile-driven and avoid clinic-specific constants so future clinic clones can reuse the same adapters.

## Planned extension points

- Publish selected FHIR events (encounter completed, order placed) to Pub/Sub.
- Add an imaging order adapter that can call a PACS/DICOM workflow in another repo.
- Keep integration behind APIs so EMR onboarding remains decoupled.

## Non-goals right now

- No direct DICOM ingestion
- No Orthanc deployment
- No imaging AI processing in this repo
