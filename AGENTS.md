# AGENTS RULES

## Secrets

Use secrets in github actions for CI/CD pipelines.

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
AWS_ACCOUNT_ID
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
OPENAI_API_KEY
```

## AWS resources prefix

Fpor all AWS resources, use the following prefix:

```text
rcoauth2
```

## GITHUB CLI

Use PAT to login github

```bash
echo "ghp_your_personal_access_token_here" | gh auth login --with-token
```

```ps
"ghp_your_personal_access_token_here" | gh auth login --with-token
```



