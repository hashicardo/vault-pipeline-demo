# Customer Brief — Vault Dynamic Secrets Demo

## What you're seeing

This demo answers a question that keeps security teams up at night:

> "How do you give a CI/CD pipeline access to a production database without
>  putting a credential somewhere an attacker could find it?"

The answer: **you don't put a credential anywhere — you generate one, use it,
and let it disappear.**

---

## The flow, step by step

### 1. No stored secrets

The pipeline authenticates using your **existing Azure Active Directory
identity** — the same identity your organisation already manages and audits.
There is no Vault token stored in GitHub. There is no database password
committed to the repo or baked into the runner image. Nothing to rotate.
Nothing to leak.

### 2. One credential, one pipeline run

Vault issues a **unique database username and password** the moment the
pipeline asks for it. That credential has never existed before and will never
exist again. It belongs to this pipeline run only.

### 3. It actually works

The pipeline connects to PostgreSQL *as that ephemeral user* and writes a row
to the `secret_log` table. The web UI on the second screen shows you exactly
who connected and when. The countdown starts the moment the credential is
issued.

### 4. Five minutes later — it's gone

Not rotated. Not revoked on a schedule. **Gone.** Vault drops the role from
PostgreSQL automatically when the TTL expires. If an attacker captured the
credential in transit, they have a five-minute window — after which it's
worthless.

### 5. Run it again

Trigger the pipeline a second time. You get a completely different username.
The previous one no longer exists. There is no shared secret between runs.

---

## Why this matters for your organisation

| Traditional approach | This approach |
|---|---|
| Long-lived DB password in a secrets manager | Credential exists for 5 minutes |
| Rotation is a manual or scheduled process | Rotation is automatic — every run |
| Breach of the credential = persistent access | Breach = 5-minute window at most |
| Audit log shows "service account connected" | Audit log shows exactly which pipeline run |

---

## What's running under the hood

- **HashiCorp Vault (HCP Dedicated)** — issues credentials and enforces TTLs
- **Azure Entra ID** — provides identity; GitHub OIDC exchanges for Azure token
- **PostgreSQL 16** — the target database; Vault creates and drops roles dynamically
- **GitHub Actions self-hosted runner** — executes the pipeline on your own EC2
- **Flask web UI** — reads the `secret_log` table and displays the live countdown
