
**Group 1: Domain Prerequisites (No Traffic Changes)**

1. Confirm DNS ownership and where records are managed.
2. Confirm hosted zone exists for ray-chunkit-chung.click.
3. Confirm frontend cert must be in us-east-1 (CloudFront requirement) and API cert in your API region.
4. Verification gate: you can create DNS records and ACM certificates in the right accounts/regions.

**Group 2: Frontend TLS Certificate Only**

1. Create ACM certificate for <www.ray-chunkit-chung.click> in us-east-1.
2. Create DNS validation record(s).
3. Wait for certificate status Issued.
4. Verification gate: cert is issued, but CloudFront still serves old default domain.

**Group 3: Frontend Domain Cutover**

1. Add <www.ray-chunkit-chung.click> as CloudFront alternate domain.
2. Attach the new ACM certificate to CloudFront.
3. Create DNS alias record www -> CloudFront.
4. Verification gate:
5. <https://www.ray-chunkit-chung.click> loads frontend.
6. Browser TLS certificate is valid.
7. Existing default CloudFront domain can still be kept as fallback temporarily.

**Group 4: Auth URL Alignment**

1. Change frontend base URL configuration to <https://www.ray-chunkit-chung.click>.
2. Update Cognito app client callback/logout URLs to use www domain.
3. Update CI build inputs so frontend uses www URL for redirect/logout.
4. Verification gate:
5. Login starts from www.
6. Callback returns to /auth/callback on www.
7. Logout returns to www home.

**Group 5: API TLS Certificate and Custom Domain**

1. Create ACM certificate for api.ray-chunkit-chung.click in API region.
2. Create DNS validation record(s).
3. Create API Gateway custom domain and map it to existing $default stage.
4. Create DNS alias api -> API Gateway custom domain.
5. Verification gate:
6. <https://api.ray-chunkit-chung.click/chat/health> returns 200.
7. Old execute-api URL still works during transition.

**Group 6: API URL and CORS Finalization**

1. Publish API base URL as <https://api.ray-chunkit-chung.click> in shared config/SSM.
2. Ensure backend CORS allow-origin includes <https://www.ray-chunkit-chung.click>.
3. Redeploy frontend so browser calls new api domain.
4. Verification gate:
5. Chat works end-to-end from www to api.
6. No CORS errors in browser devtools.

**Group 7: Stabilization and Cleanup**

1. Keep old endpoints for a short observation window.
2. Monitor auth and API logs for errors.
3. Optionally remove temporary fallback references after stable period.
4. Verification gate: no auth/API regressions over agreed observation period.

If you want, I can next turn this into an execution checklist with exact “apply + verify” commands per group so you can run each gate one by one.
