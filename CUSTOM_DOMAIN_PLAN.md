# Custom Domain Plan (Approved)

## Final decisions

1. Frontend canonical URL is <https://www.ray-chunkit-chung.click>.
2. Apex ray-chunkit-chung.click redirects to www with HTTP 301.
3. Backend canonical API URL is <https://api.ray-chunkit-chung.click>.
4. No rollback window.
5. New domains are strict and legacy endpoints are disabled.
6. Keep implementation simple, minimal, and modular.

## Phase 1: Prerequisites

1. Confirm Route53 hosted zone exists for ray-chunkit-chung.click in the same AWS account.
2. Confirm frontend certificate region is us-east-1 (CloudFront requirement).
3. Confirm backend certificate region matches API Gateway region (ap-northeast-1).
4. Verification gate: ACM and Route53 permissions are available in this account.

## Phase 2: Frontend domain and apex redirect

1. Request one ACM certificate in us-east-1 with SANs for:
1. <www.ray-chunkit-chung.click>
1. <ray-chunkit-chung.click>
1. Create DNS validation records in Route53 and wait for Issued.
1. Update CloudFront distribution:
1. Add aliases for www and apex.
1. Attach ACM certificate from us-east-1.
1. Add Route53 alias records:
1. www -> CloudFront
1. apex -> CloudFront
1. Update CloudFront Function logic:
1. If host is apex, return 301 redirect to www.
1. Allow only apex and www hosts.
1. Reject other hosts, including default cloudfront.net host.
1. Verification gate:
1. <https://www.ray-chunkit-chung.click> loads the app.
1. <https://ray-chunkit-chung.click> redirects to www.
1. CloudFront default hostname no longer serves the app.

## Phase 3: Auth alignment to canonical frontend

1. Set frontend_base_url to <https://www.ray-chunkit-chung.click>.
2. Ensure Cognito callback and logout URLs allow only canonical www URL.
3. Ensure frontend build env values use canonical www URL.
4. Verification gate:
5. Login starts on www.
6. Callback returns to /auth/callback on www.
7. Logout returns to www.

## Phase 4: API custom domain

1. Request ACM certificate in API region for api.ray-chunkit-chung.click.
2. Create DNS validation records in Route53 and wait for Issued.
3. Create API Gateway custom domain.
4. Map custom domain to existing HTTP API $default stage with no base path.
5. Create Route53 alias:
6. api -> API Gateway custom domain target.
7. Publish API base URL in SSM as <https://api.ray-chunkit-chung.click>.
8. Verification gate:
9. <https://api.ray-chunkit-chung.click/chat/health> returns 200.

## Phase 5: Strict legacy endpoint disablement

1. Disable API Gateway default execute-api endpoint.
2. Keep CloudFront host allowlist enforcement so default cloudfront.net host is blocked.
3. Remove legacy endpoint references from workflow summaries and docs.
4. Verification gate:
5. execute-api endpoint is inaccessible.
6. cloudfront.net hostname is blocked.
7. Only www and api custom domains are active.

## Phase 6: Minimal CI/CD adjustments

1. Keep SSM as single source of truth for runtime URLs.
2. Frontend workflow reads canonical frontend URL and canonical API URL from SSM parameters:
3. /rcoauth2/frontend/frontend-base-url
4. /rcoauth2/backend/chat-api-url
5. Frontend build uses only:
6. NEXT_PUBLIC_COGNITO_REDIRECT_URI = <https://www.ray-chunkit-chung.click/auth/callback>
7. NEXT_PUBLIC_COGNITO_LOGOUT_URI = <https://www.ray-chunkit-chung.click>
8. NEXT_PUBLIC_CHAT_API_BASE_URL = <https://api.ray-chunkit-chung.click>
9. Verification gate:
10. Frontend deployment works with no CloudFront default URL dependency.
11. Chat works end-to-end via www -> api.

## Phase 7: Done criteria

1. Only custom domains are reachable for end users.
2. OAuth works only on canonical www origin.
3. API traffic flows only through api.ray-chunkit-chung.click.
4. Docs and workflows no longer guide users to legacy endpoints.
