# AWS OAuth 2.0 Example

## Secrets

Use these GitHub Actions secrets for CI/CD:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
AWS_ACCOUNT_ID
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
OPENAI_API_KEY
```

## AWS Resource Prefix

All AWS resources use this prefix:

```text
rcoauth2
```

## Current Architecture

This project is a static Next.js frontend on CloudFront/S3 with Google login via Cognito Hosted UI, plus a Python Lambda chat backend behind API Gateway.

- Frontend app: Next.js static export (`frontend/out`)
- Static hosting: S3 (`rcoauth2-static`)
- CDN/edge: CloudFront + CloudFront Function rewrite
- DNS/TLS: Route53 + ACM (us-east-1) for apex and www custom domains
- Auth broker: Cognito User Pool + Hosted UI domain
- External identity provider: Google OAuth 2.0
- API: API Gateway HTTP API
- Compute: Lambda (`python3.13`)
- Data store: DynamoDB (`rcoauth2-chat`)
- Secret store: AWS Secrets Manager (`rcoauth2/backend/openai-api-key`)
- CI/CD: GitHub Actions (`.github/workflows/frontend.yml`, `.github/workflows/backend.yml`)

Production entrypoint:

- `https://www.ray-chunkit-chung.click`

Also supported:

- `https://ray-chunkit-chung.click` (301 redirect to `www`)

```mermaid
flowchart LR
  U[User Browser]
  CF[CloudFront]
  S3[S3 Static Site Bucket]
  COG[Cognito Hosted UI]
  G[Google OAuth]
  API[API Gateway HTTP API]
  L[Lambda Python 3.13]
  DDB[DynamoDB]
  SM[Secrets Manager]
  OAI[OpenAI API]

  U --> CF
  CF --> S3

  U --> COG
  COG --> G
  G --> COG
  COG --> U

  U --> API
  API --> L
  L --> DDB
  L --> SM
  L --> OAI
```

## Terraform Stack Layout

### Frontend Stack (`infra/frontend`)

Creates and maintains:

- S3 bucket + restrictive public access policy
- CloudFront distribution + OAC + route rewrite function
- ACM certificate validation + Route53 apex/www alias records
- Cognito user pool, Google identity provider, domain, app client
- SSM parameters used by frontend deploy and backend auth setup

### Backend Stack (`infra/backend`)

Creates and maintains:

- Lambda function + IAM role/policy + log group
- API Gateway HTTP API + JWT authorizer + routes + stage
- DynamoDB chat table
- Secrets Manager secret metadata (secret value injected by CI)
- SSM parameters for backend runtime/config lookup

Terraform state backend for backend stack:

- S3 state file: `s3://rcoauth2-terraform-state/backend/terraform.tfstate`
- Locking table: `rcoauth2-terraform-locks`

Backend Terraform guide for detailed planning and refactor notes:

- `infra/backend/README.md`

## Cross-Stack Contracts (SSM)

Backend reads frontend-created Cognito values:

- `/rcoauth2/frontend/cognito-user-pool-id`
- `/rcoauth2/frontend/cognito-user-pool-client-id`

Frontend deploy reads backend-created API value:

- `/rcoauth2/backend/chat-api-url`

Backend also writes:

- `/rcoauth2/backend/openai-secret-arn`
- `/rcoauth2/backend/chat-table-name`

## Authentication Flow (Browser + Cognito + Google)

Frontend implementation uses Authorization Code + PKCE in the browser.

1. User opens `/login` and clicks Continue with Google.
2. Frontend generates `code_verifier`, `code_challenge`, and `state`.
3. Browser is redirected to Cognito `/oauth2/authorize` with `identity_provider=Google`.
4. User completes Google auth; Cognito redirects to `/auth/callback?code=...&state=...`.
5. Callback page verifies `state` from session storage.
6. Frontend exchanges `code` at Cognito `/oauth2/token`.
7. Frontend stores `id_token`, `access_token`, and expiry in `sessionStorage`.
8. Frontend uses the `id_token` as `Authorization: Bearer ...` for chat API requests.
9. Sign-out clears browser session and redirects to Cognito `/logout`.

```mermaid
sequenceDiagram
  actor U as User
  participant FE as Frontend (Browser)
  participant C as Cognito Hosted UI
  participant G as Google OAuth

  U->>FE: Click Continue with Google
  FE->>FE: Generate PKCE + state
  FE->>C: GET /oauth2/authorize
  C->>G: Redirect for login
  G-->>C: User authenticated
  C-->>FE: Redirect /auth/callback?code&state
  FE->>FE: Validate state
  FE->>C: POST /oauth2/token (code + verifier)
  C-->>FE: id_token + access_token
  FE->>FE: Store session in sessionStorage
```

## Runtime Data Flow

### Frontend Runtime

1. Browser loads static pages from CloudFront.
2. CloudFront function rewrites extensionless routes, for example:
   - `/login` -> `/login.html`
   - `/auth/callback` -> `/auth/callback.html`
3. CloudFront fetches objects from private S3 via OAC.
4. 403/404 responses are mapped to `index.html` for SPA fallback.
5. Frontend checks local session state:
   - unauthenticated users are redirected to `/login`
   - authenticated users can load sessions/messages
6. Chat UI behavior: message composer uses `Enter` for newline and `Shift+Enter` to send, and users can delete a single session from the sidebar.

### Backend Runtime

Routes:

- `GET /chat/health` (public)
- `GET /chat/sessions` (JWT required)
- `GET /chat/sessions/{sessionId}` (JWT required)
- `DELETE /chat/sessions/{sessionId}` (JWT required)
- `POST /chat/messages` (JWT required)

Message request lifecycle (`POST /chat/messages`):

1. Validate JWT and extract Cognito `sub`.
2. Validate input (`message`, optional `sessionId`, max length).
3. Create session when needed (title generated from first message).
4. Save user message in DynamoDB.
5. Load bounded message history and call OpenAI.
6. Save assistant message.
7. Update session metadata (`updatedAt`, preview, message count).
8. Return updated session + both messages.

Delete session lifecycle (`DELETE /chat/sessions/{sessionId}`):

1. Validate JWT and extract Cognito `sub`.
2. Validate `sessionId` path parameter.
3. Verify the target session belongs to the authenticated user.
4. Query all messages under that session.
5. Delete all matching message items and the session metadata item.
6. Return deletion summary (`sessionId`, `deletedMessageCount`).

Data isolation model:

- Partition key: `USER#{sub}`
- Session sort key: `SESS#{sessionId}`
- Message sort key: `MSG#{sessionId}#{timestamp}#{messageId}`

This enforces per-user isolation by Cognito subject.

## CI/CD Data Flow

### Frontend Workflow (`.github/workflows/frontend.yml`)

1. Terraform job applies frontend infrastructure.
2. Deploy job reads SSM + CloudFront values.
3. Build injects `NEXT_PUBLIC_*` auth and API variables.
4. Verifies `out/auth/callback.html` exists.
5. Syncs static export to S3.
6. Invalidates CloudFront cache.

### Backend Workflow (`.github/workflows/backend.yml`)

1. Builds Lambda package (`backend/build.sh` -> `backend/dist/lambda.zip`).
2. Runs Terraform init/fmt/validate/plan/apply in `infra/backend`.
3. Reads backend SSM values (`chat-api-url`, `openai-secret-arn`).
4. Updates secret value in Secrets Manager from `OPENAI_API_KEY`.
5. Runs health endpoint smoke test.

## Configuration Mapping

### Frontend Build-Time Env Vars

- `NEXT_PUBLIC_COGNITO_DOMAIN`
- `NEXT_PUBLIC_COGNITO_CLIENT_ID`
- `NEXT_PUBLIC_COGNITO_REDIRECT_URI`
- `NEXT_PUBLIC_COGNITO_LOGOUT_URI`
- `NEXT_PUBLIC_CHAT_API_BASE_URL`

### Terraform Inputs

- Frontend: `google_client_id`, `google_client_secret`
- Backend: `project_prefix`, `frontend_base_url`, `openai_model`, `enable_lambda_warmup`, `lambda_warmup_interval_minutes`

## Local Development Notes

### Frontend

```bash
pnpm dev
```

### Backend Terraform Validate Pitfall

`terraform validate` for `infra/backend` will fail if Lambda zip is missing because `filebase64sha256` reads:

- `../../backend/dist/lambda.zip`

Build it first:

```bash
chmod +x backend/build.sh
./backend/build.sh
```

## Route53

Route53/custom domains are in use.

- Apex: `ray-chunkit-chung.click`
- Canonical: `www.ray-chunkit-chung.click`
- Apex requests are redirected to `www` by the CloudFront Function.
