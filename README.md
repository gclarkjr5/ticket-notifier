# ticket-notifier

Get an instant phone alert, with the buy link, when Celebratix emails a resale ticket for
SPIELRAUM WEEKENDER OCT. You tap the notification and complete the purchase yourself.

```
Gmail ─watch→ Pub/Sub ─push (OIDC)→ Cloud Run: ticket-alert (Rust) ─→ ntfy ─→ phone
                                          ↑
              Cloud Scheduler (daily /renew keeps the Gmail watch alive)
```

| path | what |
|---|---|
| `ticket-alert/` | the Rust service and its Dockerfile |
| `infra/` | OpenTofu for all of GCP: APIs, registry, secrets, Cloud Run, Pub/Sub, Scheduler, IAM, GitHub OIDC |
| `.github/workflows/` | CI (`ci.yml`) and plan/deploy (`infra.yml`) |
| `justfile` | local commands; run `just` to list them (needs [just](https://just.systems)) |

GCP project: `ticket-notifier-511415`. Region: `europe-west4`.

## One-time setup (from your laptop)
1. `gcloud auth login && gcloud auth application-default login`; install OpenTofu, just, and optionally `gh`.
2. **OAuth client** (console only): APIs & Services → OAuth consent screen (External, add yourself as test user, then **Publish app**; apps left in "Testing" expire the refresh token after 7 days) → Credentials → OAuth client ID (Desktop). Authorize once with scope `https://www.googleapis.com/auth/gmail.modify` (e.g. OAuth Playground with "Use your own OAuth credentials") and keep the refresh token.
3. Install **ntfy** on your phone, subscribe to a long random topic, and allow urgent notifications to override Do Not Disturb.
4. `cp infra/terraform.tfvars.example infra/terraform.tfvars` and fill it in (git-ignored). `github_repository` is `OWNER/REPO` of this repo once you push it.
5. Deploy the first time by hand:
   ```sh
   just bootstrap   # state bucket, APIs, image registry
   just image       # Cloud Build builds and pushes the container
   just deploy      # everything else (review the plan, type yes)
   just watch       # start the Gmail watch now
   ```

## Hand over to GitHub Actions
Push the repo to GitHub, then:
```sh
just ci-vars     # sets GCP_WORKLOAD_IDENTITY_PROVIDER and GCP_DEPLOYER_SA repo variables
gh secret set GOOGLE_CLIENT_ID
gh secret set GOOGLE_CLIENT_SECRET
gh secret set GOOGLE_REFRESH_TOKEN
gh secret set NTFY_TOPIC
```
Auth is keyless (Workload Identity Federation limited to this repository); no JSON keys.
Optional: in Settings → Environments → `production`, add yourself as a required reviewer to
gate deploys.

| workflow | when | does |
|---|---|---|
| `ci.yml` | every PR and push to `main` | `cargo fmt --check`, `clippy -D warnings`, tests; hadolint + Docker build; `tofu fmt -check` + `validate` |
| `infra.yml` → plan | PR touching `infra/` or `ticket-alert/` | `tofu plan`, posted/updated as a PR comment |
| `infra.yml` → deploy | merge to `main` | build + push image tagged with the commit SHA, then `tofu apply` |
| dependabot | weekly | Actions, cargo, Docker and provider updates |

Suggested branch protection on `main`: require the three `ci.yml` jobs and the plan job.

## Day to day
- `just lint` runs the same checks as CI locally; `just fmt` fixes formatting.
- Merge to `main` to deploy. `just image deploy` still works for a manual deploy.
- `just logs` tails the service.

## Test the alert
Temporarily `tofu -chdir=infra apply -var sender=<your own address>` (or edit the tfvars),
mail yourself a message with a `https://shop.celebratix.io/resale/...` link, and confirm the
phone buzzes within seconds. Set it back afterwards.

## Notes
- OAuth secrets and the ntfy topic live in OpenTofu state (GCS bucket `ticket-notifier-511415-tfstate`, versioned, private) and in GitHub secrets.
- The deployer service account holds admin roles on the services used here (see `infra/github.tf`). PR plans from forks get no cloud access; keep the repo private or restrict who can open PRs.
- If a Celebratix button is a tracking redirect on another domain, you'll get a "no link matched" alert; adjust `link_pattern`.
- The first apply can fail on the Pub/Sub token-creator binding if Google hasn't created the Pub/Sub service agent yet; rerun `just deploy`.
