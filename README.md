# AWS OAuth 2.0 Example

## Secrets

Use secrets in github actions for CI/CD pipelines.

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
AWS_ACCOUNT_ID
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
```

## AWS resources prefix

Fpor all AWS resources, use the following prefix:

```text
rcoauth2
```

## Frontend

### Getting Started

First, run the development server:

```bash
pnpm dev
```

## Backend

to be added

## Google OAuth + Cognito Setup

This project uses Cognito Hosted UI and federates Google as an external identity provider.

Production frontend base URL used for OAuth setup:

- `https://ray-chunkit-chung.click`

In Google Cloud OAuth client settings:

- Authorized redirect URIs:
  - `https://<cognito-domain>/oauth2/idpresponse`
- Authorized JavaScript origins:
  - Not required for Cognito Hosted UI federation. Leave empty unless Google Console requires values.

Example redirect URI for this project:

- `https://rcoauth2-auth.auth.ap-northeast-1.amazoncognito.com/oauth2/idpresponse`

Frontend `.env.local` values are based on `frontend/.env.local.example`.

## Route53

```text
https://ray-chunkit-chung.click
```
