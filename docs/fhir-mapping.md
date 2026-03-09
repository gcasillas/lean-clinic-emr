# FHIR Mapping Notes

## Resource mapping in sandbox

- Patient demographics -> `Patient`
- Visit metadata -> `Encounter`
- Pain and ROM snapshots -> `Observation`
- Rehab plan text -> `CarePlan`

## Notes

- Current scripts generate a minimal R4-compatible transaction bundle.
- Mapping is intentionally simple to keep onboarding clear.
- You can expand this with `Condition`, `Procedure`, and `MedicationRequest` as workflows mature.

## Holistic/herbal extension plan

### Required custom forms/fields in OpenEMR

1. Intake form:
- Lifestyle pattern summary
- Diet pattern summary
- Stress and sleep screening
- Patient goals

2. Herbal protocol form:
- Protocol name and rationale
- Herb ingredients and dosage schedule
- Route and duration

3. Contraindication form:
- Pregnancy/lactation flags
- Chronic conditions risk flags
- Known herb allergy list

4. Supplement interaction tracking:
- Current medications
- Potential herb-drug interactions
- Severity and mitigation plan

5. Follow-up cadence:
- Follow-up interval target
- Objective check metrics
- Protocol adjustment decision

### OpenEMR and FHIR mapping targets

- Intake form:
`forms` + patient encounter notes -> `QuestionnaireResponse`, `Condition`, `Observation`

- Herbal protocol:
Custom form table + prescriptions/notes -> `CarePlan`, `MedicationRequest`, `MedicationStatement`

- Contraindications:
Problem list/allergy tables -> `AllergyIntolerance`, `Condition`

- Supplement interactions:
Medication lists + clinical notes -> `DetectedIssue`, `MedicationStatement`, `Observation`

- Follow-up cadence:
Appointment and encounter schedule fields -> `Appointment`, `CarePlan.activity.detail.scheduledTiming`, `Encounter`

### Implementation notes

- Keep custom form schemas profile-specific where possible.
- Keep migration code generic by mapping profile field keys to FHIR transformers.
- Validate terminology alignment (SNOMED CT/RxNorm where available) before production exchange.
