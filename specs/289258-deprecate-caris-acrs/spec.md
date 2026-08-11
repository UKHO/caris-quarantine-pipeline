# Feature Specification: Deprecate legacy CARIS ACRs — quarantine pipeline promotion targets

**Feature Branch**: `289258-deprecate-caris-acrs`

**Created**: 2026-08-10

**Status**: Draft

**Source PBI**: Azure DevOps #289258

**Repository scope**: caris-quarantine-pipeline (one slice of a multi-repo PBI fan-out)

**Input**: Remove carispreacr and carisliveacr as promotion targets from the quarantine supply-chain pipeline so that scanned images are delivered only to globalpreacr and globalliveacr, enforcing the standard ingestion path (publiccrlive → quarantine → global ACRs).

## Clarifications

### Session 2026-08-10 (inherited from PBI-level fan-out)

- Q: Environment-to-registry mapping? → A: Dev/Dev2/PRE use globalpreacr; STG and LIVE use globalliveacr (STG mirrors the LIVE tier).
- Q: Are the blocking PBIs (288516 quarantine delivery to global ACRs, 289224 Teledyne transition) resolved? → A: Both complete; the global-ACR delivery path already exists, so this slice removes the legacy targets rather than adding the global ones.
- Q: Rollback path? → A: None required; validation is forward — run the pipeline for a representative image and confirm delivery only to the global registries.
- Q: Repository scope for this run? → A: Multi-repo fan-out; this spec covers only the caris-quarantine-pipeline slice. GitOps references live in caris-bootstrap/caris-services/ukho-backstage and Terraform/decommission in caris-infra.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quarantine pipeline promotes only to the global registries (Priority: P1)

As a platform engineer responsible for the image supply chain, I want the quarantine pipeline to promote scanned images only to globalpreacr and globalliveacr and to no longer push to carispreacr or carisliveacr, so that the deprecated registries stop receiving images and can be safely decommissioned.

**Why this priority**: While the pipeline still pushes to the legacy registries they cannot be decommissioned and drift can reappear; stopping legacy promotion is the whole purpose of this slice.

**Independent Test**: Inspect the pipeline templates and confirm carispreacr/carisliveacr (registries, service connections, and legacy push stages) are not present as targets; run the pipeline for a representative image and confirm it is delivered only to the global registries.

**Acceptance Scenarios**:

1. **Given** the quarantine pipeline configuration and templates, **When** promotion targets are inspected, **Then** carispreacr and carisliveacr are not present as targets, variables, or service connections.
2. **Given** a scanned image passing quarantine, **When** the pipeline promotes it, **Then** it is delivered only to globalpreacr and/or globalliveacr.
3. **Given** the pipeline stage list, **When** it runs end to end, **Then** the legacy push stages (e.g. PushToPreACR/PushToPrivateRepo for the caris registries) are gone and the global push stages succeed.

---

### User Story 2 - Pipeline documentation reflects the global-only supply chain (Priority: P2)

As a platform engineer maintaining the quarantine pipeline, I want the repository README/docs to describe the global-only ingestion path so operators do not reintroduce legacy targets.

**Why this priority**: Prevents regression and clarifies the supported path, but does not affect pipeline behaviour, so it follows the target removal.

**Independent Test**: Review the pipeline README and confirm it documents delivery to globalpreacr/globalliveacr only and contains no active guidance to push to the legacy registries.

**Acceptance Scenarios**:

1. **Given** the pipeline README, **When** searched for the legacy registries, **Then** any remaining mentions are historical/deprecation notes only.

---

### Edge Cases

- A legacy service connection (e.g. `carisliveacr-docker`, `carispreacr-docker`) may remain referenced by a stage even after the registry variable is removed; both must be removed together to avoid a broken pipeline.
- Removing a stage must not break stage dependencies (`dependsOn`) of downstream global-push stages.
- If the global push stages were gated behind the same condition as legacy stages, the condition must be preserved for the global path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The quarantine pipeline MUST NOT promote images to carispreacr or carisliveacr.
- **FR-002**: The pipeline MUST deliver scanned images only to globalpreacr and/or globalliveacr.
- **FR-003**: Legacy registry variables, service connections, and push stages for carispreacr/carisliveacr MUST be removed from the pipeline templates without breaking the remaining stage dependencies.
- **FR-004**: The pipeline MUST run successfully end to end after the legacy targets are removed, delivering a representative image to the global registries.
- **FR-005**: Pipeline documentation MUST be updated to describe the global-only ingestion path and remove active guidance to use the legacy registries.
- **FR-006**: Changes MUST be limited to the caris-quarantine-pipeline repository; GitOps and Terraform changes are tracked in their own repositories.

### Key Entities

- **Legacy targets**: carispreacr (`carispreacr.azurecr.io`), carisliveacr (`carisliveacr.azurecr.io`), and their `*-docker` service connections — to be removed.
- **Global targets**: globalpreacr, globalliveacr — the only remaining promotion destinations.
- **Pipeline templates**: `templates/common-variables.yml` (registry vars + service connections) and `templates/container-scan-template.yml` (push stages).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The quarantine pipeline promotes to exactly two registries (globalpreacr, globalliveacr) and zero legacy registries.
- **SC-002**: A representative image run delivers to the global registries with zero pushes to carispreacr/carisliveacr and no pipeline failures.
- **SC-003**: Pipeline documentation contains no active guidance to push to the legacy registries.

## Assumptions

- The global-ACR delivery stages already exist in the pipeline (PBI 288516 complete); this slice removes the legacy stages/targets rather than adding global ones.
- The `globalpreacr`/`globalliveacr` variables and service connections are already present and working.
- No dedicated rollback path is maintained; validation is a forward pipeline run against a representative image.
- GitOps reference updates (caris-bootstrap/caris-services/ukho-backstage) and Terraform removal/decommission (caris-infra) are owned by their own repositories; they sequence before final decommission but are not part of this slice.
