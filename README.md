# CARIS Quarantine Pipeline

An Azure DevOps pipeline that implements a container quarantine flow for enhanced security. This pipeline automatically scans Docker container images for vulnerabilities using Snyk and only promotes clean images to a private registry.

## Overview

This pipeline provides an automated security gate for container images by:
1. **Triggering** on container registry webhooks when new images are pushed
2. **Scanning** images for security vulnerabilities using Snyk
3. **Promoting** clean images to a secure private registry
4. **Alerting** on failed scans to prevent vulnerable images from being deployed

## Pipeline Flow

### 1. Webhook Trigger
- Monitors Azure Container Registry (ACR) for new image pushes
- Triggers automatically when images with media type `application/vnd.oci.image.index.v1+json` are pushed
- Extracts image details (repository, tag, host) from the webhook payload

### 2. Container Scanning Stage
- **Pulls** the newly pushed image from the source registry
- **Scans** the image using Snyk container scanning with:
  - Organization: `caris-cloud`
  - Severity threshold: `high` (fails on high/critical vulnerabilities)
  - Fail-fast behavior to prevent vulnerable images from proceeding

### 3. Image Promotion Stage (On Success)
- **Executes** only if the security scan passes
- **Pulls** the verified image from source registry
- **Tags** the image with `-snyk-scanned` suffix to indicate it has passed security checks
- **Pushes** the tagged image to the destination registry under the `scanned/` repository prefix

### 4. Alert Stage (On Failure)
- **Triggers** only if the security scan fails
- **Sends** Teams notification (if webhook endpoint is configured) about the vulnerable image
- **Logs** failure details for audit purposes

## Configuration

### Required Service Connections
- `source-docker-registry-connection`: Access to the source container registry
- `destination-docker-registry-connection`: Access to the destination private registry
- `Snyk Auth`: Snyk service connection for vulnerability scanning

### Variables
- **Source Registry**: Configured via webhook trigger
- **Destination Registry**: `myregistry.azurecr.io`
- **Snyk Organization**: `caris-cloud`
- **Teams Webhook**: Optional notification endpoint for scan failures

## Image Naming Convention

**Source**: `{source-registry}/{repository}:{tag}`

**Destination**: `acrghpmcitodev.azurecr.io/scanned/{repository}:{tag}-snyk-scanned`

Example:
- Source: `myregistry.azurecr.io/myapp:v1.0.0`
- Destination: `myregistry.azurecr.io/scanned/myapp:v1.0.0-snyk-scanned`

## Security Benefits

- **Vulnerability Prevention**: Only images that pass Snyk security scans are promoted
- **Traceability**: Clear naming convention indicates which images have been security validated
- **Automated Enforcement**: No manual intervention required - security is built into the deployment pipeline
- **Alert System**: Immediate notification when vulnerable images are detected

## Prerequisites

1. Azure DevOps environment with required service connections
2. Snyk account and organization setup
3. Source and destination Azure Container Registries
4. UkhoSnykScanTask extension installed in Azure DevOps
5. Webhook connection configured between source ACR and Azure DevOps
