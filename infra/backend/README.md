# Backend Terraform Guide

This document explains how the backend Terraform stack works so new users and agents can safely plan changes.

## What This Stack Manages

Files in this folder manage the backend infrastructure for the chat API:

- HTTP API (API Gateway v2)
- Lambda function (Python 3.13)
- DynamoDB chat table
- Secrets Manager secret for OpenAI API key
- IAM role and policy for Lambda
- CloudWatch log group
- SSM parameters used by CI/CD and apps

State is stored remotely in S3 (see providers.tf):

- Bucket: rcoauth2-terraform-state
- State key: backend/terraform.tfstate
- Region: ap-northeast-1

## How The Pieces Connect

1. Frontend authenticates users via Cognito.
2. API Gateway receives backend requests.
3. JWT-protected routes validate Cognito tokens with a JWT authorizer.
4. API Gateway forwards requests to Lambda.
5. Lambda reads/writes chat data in DynamoDB.
6. Lambda reads OpenAI key from Secrets Manager.
7. Terraform writes backend runtime values to SSM for CI/CD and runtime config.

## Route Model

Routes are split into two sets in locals:

- public_chat_routes: no auth (currently GET /chat/health)
- protected_chat_routes: JWT auth required

These sets are materialized with for_each in aws_apigatewayv2_route.public and aws_apigatewayv2_route.protected.

## Inputs, Outputs, And Cross-Stack Contract

### Inputs (variables.tf)

- project_prefix
- frontend_base_url
- frontend_local_base_url
- openai_model

### Reads From Frontend Stack

Backend reads these SSM parameters created by frontend Terraform:

- /rcoauth2/frontend/cognito-user-pool-id
- /rcoauth2/frontend/cognito-user-pool-client-id

These values are used to configure API Gateway JWT issuer/audience.

### Writes For Backend Consumers

Backend writes these SSM parameters:

- /rcoauth2/backend/chat-api-url
- /rcoauth2/backend/openai-secret-arn
- /rcoauth2/backend/chat-table-name

These are consumed by backend GitHub Actions deployment steps.

### Outputs (outputs.tf)

- chat_api_url
- chat_table_name
- openai_secret_arn

## Why moved Blocks Exist

main.tf contains moved blocks to preserve Terraform state continuity after refactors:

- old per-route resources -> new for_each route resources
- old individual SSM resources -> new for_each SSM resource

This avoids destroy/recreate behavior during refactor-only changes.

Important: moved addresses must be static references. Do not use interpolation in moved to/from addresses.

## Day-1 And Day-2 Commands

From repository root:

```bash
terraform -chdir=infra/backend init
terraform -chdir=infra/backend fmt -check
terraform -chdir=infra/backend validate
terraform -chdir=infra/backend plan
```

Apply:

```bash
terraform -chdir=infra/backend apply
```

## Common Validation Failure

If validate fails with filebase64sha256 on ../../backend/dist/lambda.zip, the Lambda artifact has not been built yet.

Build it first:

```bash
chmod +x backend/build.sh
./backend/build.sh
```

Then run validate/plan again.

## Planning Checklist For Future Changes

1. Classify change type: additive, refactor, or destructive.
2. If refactoring resource addresses, add moved blocks before apply.
3. Keep SSM parameter names stable unless consumers are updated.
4. Run fmt, validate, and plan before apply.
5. Review plan for unintended replacements.
6. If API routes/auth change, verify frontend calls and smoke test still pass.
7. If changing secret/table names, update CI workflow steps that read SSM parameters.

## CI/CD Context

Workflow: .github/workflows/backend.yml

Pipeline sequence:

1. Build Lambda package (backend/build.sh)
2. terraform init / fmt -check / validate / plan / apply
3. Read backend SSM parameters
4. Update Secrets Manager secret value from OPENAI_API_KEY
5. Smoke test GET /chat/health
