# AppConfig Frontend Runtime Plan

## Objective

Move frontend runtime configuration to AWS AppConfig while keeping the frontend runtime contract stable (`/config.json`).

Primary outcomes:

- No hardcoded backend URL in static JS bundles.
- Runtime config changes without frontend rebuild/redeploy.
- Safe rollout and fast rollback.

## Current State (Repository-Specific)

- Frontend runtime loader already exists in `frontend/lib/runtime-config.ts` and fetches `/config.json`.
- Chat API client already reads runtime `chatApiBaseUrl` from that loader.
- Frontend auth still depends on build-time `NEXT_PUBLIC_*` vars in `frontend/hooks/use-auth.ts`.
- Frontend GitHub Actions workflow currently writes `out/config.json` during deploy.
- CloudFront currently uses one default cache behavior for the whole site.

## Target Architecture

1. AppConfig stores public frontend runtime config (API URL, Cognito values, feature flags).
2. Backend exposes `GET /public/config` to read and return AppConfig JSON.
3. CloudFront routes `/config.json` to backend origin with short TTL cache policy.
4. Frontend continues to fetch `/config.json` (same path, no breaking contract).

This avoids direct browser-to-AppConfig IAM/auth complexity and keeps static assets aggressively cacheable.

## Runtime Config Contract

Required keys:

- `version` (string)
- `chatApiBaseUrl` (https URL)
- `cognitoDomain` (string)
- `cognitoClientId` (string)
- `cognitoRedirectUri` (https URL)
- `cognitoLogoutUri` (https URL)

Optional keys:

- `featureFlags` (object with boolean fields)

Example:

```json
{
  "version": "2026-04-29.1",
  "chatApiBaseUrl": "https://api.ray-chunkit-chung.click",
  "cognitoDomain": "rcoauth2-auth.auth.us-west-2.amazoncognito.com",
  "cognitoClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
  "cognitoRedirectUri": "https://www.ray-chunkit-chung.click/auth/callback",
  "cognitoLogoutUri": "https://www.ray-chunkit-chung.click",
  "featureFlags": {
	 "newSidebar": false,
	 "showSessionDeleteConfirm": true
  }
}
```

## Implementation Plan

### Phase 1 - Create AppConfig Foundation (Terraform: frontend stack)

Files:

- `infra/frontend/main.tf`
- `infra/frontend/outputs.tf`

Changes:

1. Add AppConfig application, environment, and hosted config profile.
2. Add JSON schema validator to enforce required config shape.
3. Add outputs for AppConfig identifiers.
4. Publish AppConfig IDs into SSM for backend lookup:
	- `/rcoauth2/frontend/appconfig-application-id`
	- `/rcoauth2/frontend/appconfig-environment-id`
	- `/rcoauth2/frontend/appconfig-config-profile-id`

Acceptance checks:

- Terraform plan/apply succeeds.
- AppConfig resources visible in AWS console.
- SSM parameters exist and contain expected IDs.

### Phase 2 - Backend Config Endpoint (Terraform + Lambda)

Files:

- `infra/backend/main.tf`
- `backend/src/handler.py`

Changes:

1. Read AppConfig IDs from SSM in backend Terraform.
2. Add Lambda env vars for AppConfig IDs.
3. Add IAM permissions:
	- `appconfig:StartConfigurationSession`
	- `appconfig:GetLatestConfiguration`
4. Add public API route: `GET /public/config` (no JWT authorizer).
5. Implement handler logic:
	- Fetch config from AppConfigData API.
	- Validate/parse JSON.
	- In-memory cache (15-30 seconds) to reduce repeated calls.
	- Last-known-good fallback on transient failures.
6. Return headers:
	- `Content-Type: application/json`
	- `Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=30`
	- `ETag` (recommended)
	- `x-config-version` (recommended)

Acceptance checks:

- `GET /public/config` returns 200 with required keys.
- Endpoint remains available during transient AppConfig read failures via fallback.
- CloudWatch logs show successful fetch and served version.

### Phase 3 - CloudFront Route for /config.json (Terraform: frontend stack)

File:

- `infra/frontend/main.tf`

Changes:

1. Add CloudFront API origin for backend custom domain.
2. Add ordered cache behavior for path `/config.json` to API origin.
3. Keep default behavior unchanged for static assets on S3 origin.
4. Add dedicated cache policy for config endpoint:
	- `min_ttl = 0`
	- `default_ttl = 30`
	- `max_ttl = 60`
	- exclude query strings, headers, and cookies from cache key

Acceptance checks:

- `https://www.<domain>/config.json` returns backend-served JSON.
- Changes in AppConfig appear in clients within about 30-60 seconds.
- Static asset behavior unaffected.

### Phase 4 - Frontend Runtime Auth Migration

Files:

- `frontend/lib/runtime-config.ts`
- `frontend/hooks/use-auth.ts`
- `frontend/app/login/page.tsx`
- `frontend/app/auth/callback/page.tsx`

Changes:

1. Extend runtime config type and accessors to include Cognito fields and flags.
2. Refactor auth flow to consume async runtime config (remove build-time dependency).
3. Add friendly loading/error UI for config-unavailable state.

Acceptance checks:

- Login and callback flows work using runtime config only.
- No auth-related `NEXT_PUBLIC_*` vars required for production runtime behavior.

### Phase 5 - CI/CD Simplification

File:

- `.github/workflows/frontend.yml`

Changes:

1. Transition period: keep writing `out/config.json` as fallback until Phase 4 is verified in production.
2. After verification: remove runtime config write/copy steps from frontend deploy.
3. Keep HTML/static cache controls and invalidations as needed.

Optional addition:

- Add a dedicated workflow to publish AppConfig updates independently (without frontend rebuild).

Acceptance checks:

- Frontend deploy no longer required for runtime config changes.
- AppConfig-only update path works and is auditable.

## Rollout Strategy

1. Deploy Phase 1 (AppConfig infra + SSM IDs).
2. Deploy Phase 2 (backend endpoint).
3. Validate endpoint directly at API domain.
4. Deploy Phase 3 (CloudFront `/config.json` behavior).
5. Validate `/config.json` through frontend domain.
6. Deploy Phase 4 (frontend auth runtime migration).
7. Remove workflow fallback steps in Phase 5.

## Rollback Strategy

If any regression occurs:

1. Re-enable `out/config.json` generation/upload in `.github/workflows/frontend.yml`.
2. Invalidate CloudFront `/config.json` and HTML paths.
3. Temporarily remove or deprioritize CloudFront `/config.json` API behavior.

Because frontend keeps the same `/config.json` contract, rollback is low risk.

## Security and Data Boundaries

- AppConfig payload for frontend must contain only public values.
- No secrets in frontend AppConfig profile.
- Backend endpoint must return a whitelisted schema only.
- Continue using SSM/Secrets Manager for backend secrets.

## Risks and Mitigations

1. Risk: stale config persists due to caching mistakes.
	- Mitigation: dedicated CloudFront behavior + explicit short TTL + proper response cache headers.
2. Risk: partial migration leaves auth split between runtime and build-time.
	- Mitigation: migrate all Cognito frontend runtime values in Phase 4 before removing fallback.
3. Risk: AppConfig transient outage affects bootstrap.
	- Mitigation: Lambda last-known-good in-memory cache and graceful fallback response.

## Testing Plan

Functional tests:

1. Login works end-to-end after runtime auth migration.
2. Chat API calls use runtime `chatApiBaseUrl`.
3. AppConfig change (for example API URL or feature flag) is reflected without frontend deploy.

Resilience tests:

1. Simulate temporary AppConfig read failure and confirm endpoint serves last-known-good.
2. Confirm frontend shows clear error/retry UI when config cannot load.

Cache tests:

1. Verify CloudFront and browser behavior respects short config TTL.
2. Verify static assets remain long-cache immutable.

## Definition of Done

- Frontend runtime config is sourced from AppConfig through `/config.json`.
- Frontend auth and chat config are fully runtime-driven.
- Runtime config updates no longer require frontend rebuild/redeploy.
- Rollout and rollback are documented and tested.
- Operational logs include config version and fallback indicators.

## Suggested Execution Order (PRs)

1. PR 1: AppConfig Terraform resources + SSM contracts.
2. PR 2: Backend endpoint + IAM + route.
3. PR 3: CloudFront `/config.json` behavior + cache policy.
4. PR 4: Frontend runtime auth migration.
5. PR 5: CI cleanup + optional AppConfig publish workflow.

## config.json Lifecycle Comparison (Current vs AppConfig)

### Current (Today)

How `config.json` is created:

1. Frontend workflow reads runtime values (for example backend API URL) from SSM.
2. During frontend deploy, `.github/workflows/frontend.yml` writes `frontend/out/config.json`.
3. Workflow uploads that file to S3 bucket root as `config.json`.
4. CloudFront serves `/config.json` from S3.

How `config.json` is consumed:

1. Browser loads frontend static assets from CloudFront.
2. Frontend runtime loader (`frontend/lib/runtime-config.ts`) fetches `/config.json`.
3. Chat client uses `chatApiBaseUrl` from the loaded JSON.

Operational characteristics:

- Updating config requires running frontend deployment pipeline.
- Config change is coupled to static site deployment.
- Frontend currently uses runtime config for chat URL, but auth values are still build-time.

### After AppConfig Migration

How `config.json` is created:

1. Runtime config is authored and versioned in AWS AppConfig (hosted configuration).
2. Backend endpoint (`GET /public/config`) reads active AppConfig data and returns JSON.
3. CloudFront path behavior routes `/config.json` to backend origin (not S3).
4. CloudFront caches response briefly (for example 30-60 seconds), then refreshes.

How `config.json` is consumed:

1. Browser still requests same path: `/config.json`.
2. Frontend runtime loader behavior remains unchanged (same endpoint contract).
3. Both chat API and auth config are read from runtime JSON.

Operational characteristics:

- Updating config does not require frontend rebuild/redeploy.
- Config rollout can be controlled via AppConfig deployment strategies.
- Runtime changes become visible on clients after short cache TTL.
- Safer rollback: revert AppConfig version/deployment rather than redeploying frontend assets.

### Side-by-Side Summary

| Aspect | Current | After AppConfig |
| --- | --- | --- |
| Source of truth | Workflow-generated file | AppConfig hosted configuration |
| Who writes `/config.json` | Frontend CI writes file to S3 | Backend endpoint materializes config from AppConfig |
| CloudFront origin for `/config.json` | S3 origin | API/backend origin |
| Change trigger | Frontend deploy | AppConfig deployment |
| Time to propagate | Depends on deploy + cache | Short TTL + AppConfig rollout |
| Coupling to frontend build | High | Low |
| Rollback path | Redeploy previous frontend config file | Roll back AppConfig version/deployment |

## AppConfig Deployment vs Rollout Timing

- AppConfig deployment happens when a new hosted configuration version is created and promoted to the target environment (for example `prod`) using an AppConfig deployment action.
- AppConfig rollout happens after that deployment starts, during the deployment strategy window (for example immediate, linear, or canary), and finishes when AppConfig marks the deployment as complete.
- Roll back AppConfig happens when a newly deployed configuration causes regression (for example login failure, wrong API target, or elevated error rates) and operators revert the environment to the last known good AppConfig version/deployment.
- User-visible impact happens only after rollout progresses and cache TTLs expire; in this plan, expect clients to observe changes within about 30-60 seconds after deployment reaches active state.


