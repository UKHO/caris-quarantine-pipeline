---

description: "Task list template for feature implementation"
---

# Tasks: Deprecate legacy CARIS ACRs — quarantine pipeline slice

**Input**: Design documents from `specs/289258-deprecate-caris-acrs/`
**Prerequisites**: plan.md (required), spec.md (required)

**Source PBI**: Azure DevOps #289258 (multi-repo fan-out — caris-quarantine-pipeline slice only)

**Scope**: Remove legacy promotion targets/stages from the quarantine pipeline; validate global-only delivery.

## Phase 1: Map legacy references (US1)

- [ ] T001 [US1] Enumerate every reference to the legacy registries in `templates/common-variables.yml` (`destinationRegistry=carisliveacr.azurecr.io`, `preRegistry=carispreacr.azurecr.io`, service connections `carisliveacr-docker`/`carispreacr-docker`) and in `templates/container-scan-template.yml` (stages `PushToPreACR`, `PushToPrivateRepo`); record their `dependsOn`/condition relationships with the retained global stages.

## Phase 2: User Story 1 - Pipeline promotes only to the global registries (Priority: P1) 🎯 MVP

**Goal**: The quarantine pipeline delivers scanned images only to `globalpreacr`/`globalliveacr`; no push to `carispreacr`/`carisliveacr`.

**Independent Test**: Inspect templates — no legacy targets remain; a representative pipeline run delivers only to the global registries.

- [ ] T002 [US1] Remove the legacy registry variables and the `carisliveacr-docker`/`carispreacr-docker` service-connection references from `templates/common-variables.yml`.
- [ ] T003 [US1] Remove the legacy push stages (`PushToPreACR`, `PushToPrivateRepo`) from `templates/container-scan-template.yml`, and repair any `dependsOn`/conditions on the retained `PushToGlobalPreACR`/`PushToGlobalLiveACR` stages so the global path still runs.
- [ ] T004 [US1] Validate template YAML (lint/parse) and confirm no remaining references to the removed variables, service connections, or stages.
- [ ] T005 [US1] Run the quarantine pipeline for a representative image; confirm delivery only to `globalpreacr`/`globalliveacr` with zero pushes to the legacy registries and no pipeline failures (SC-002).

**Checkpoint**: Legacy promotion targets removed and pipeline validated.

## Phase 3: User Story 2 - Documentation reflects global-only supply chain (Priority: P2)

- [ ] T006 [US2] Update `README.md` to describe the global-only ingestion path (publiccrlive → quarantine → `globalpreacr`/`globalliveacr`) and convert any legacy-registry mention to a historical/deprecation note.

**Checkpoint**: Documentation updated.

## Dependencies & Execution Order

- T001 (map) precedes T002/T003.
- T002 and T003 must be done together (variable + service connection + stage) to avoid a broken pipeline; then T004 → T005.
- T006 (docs) can proceed once T001 is done.
- Cross-repo sequencing: this slice should complete before caris-infra decommission so legacy registries stop receiving images before removal.

## Traceability to PBI child tasks

| PBI child task | quarantine-pipeline tasks |
|----------------|---------------------------|
| 4 Pipeline Update | T001, T002, T003, T004, T005 |
| 8 Documentation | T006 |

## Notes

- Global push stages already exist (PBI 288516 complete); this is a removal, not an addition.
- Removing a legacy service connection must not disturb global-registry authentication.
- No dedicated rollback; validation is a forward pipeline run.
