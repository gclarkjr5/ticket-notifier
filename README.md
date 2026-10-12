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
| `justfile` | every action, used by you and by CI; run `just` to list them (needs [just](https://just.systems)) |

GCP project: `ticket-notifier-511415`. Region: `europe-west4`.

## One-time setup (from your laptop)
1. `gcloud auth login && gcloud auth application-default login`; install OpenTofu, just, and optionally `gh`.
2. **Gmail OAuth** (Google Cloud console only, one time). The app stays in *Testing* mode (no publishing, branding or domain needed), which means Google expires the refresh token after **7 days**; see "Token rotation" below. First `gcloud services enable gmail.googleapis.com --project ticket-notifier-511415`, then in the console:
   1. **Google Auth Platform → Get started**: app name `ticket-notifier`, your email as support and contact email, Audience **External**, accept the policy, Create.
   2. **Data Access → Add or remove scopes**: add `https://www.googleapis.com/auth/gmail.modify` (paste it under "Manually add scopes" if it isn't listed), Update, Save.
   3. **Audience → Test users → Add users**: add your own Gmail address. Leave the app in Testing.
   4. **Clients → Create client**: type **Web application**, authorized redirect URI `https://developers.google.com/oauthplayground`. Copy the client ID and secret.
   5. Open the [OAuth Playground](https://developers.google.com/oauthplayground), click the gear, tick **Use your own OAuth credentials**, paste the client ID and secret. In step 1 enter the scope `https://www.googleapis.com/auth/gmail.modify` and Authorize APIs. Choose your Gmail account; on the "Google hasn't verified this app" screen click Advanced → Go to ticket-notifier (unsafe), which is your own app. In step 2 click **Exchange authorization code for tokens** and copy the **refresh token**.
3. Install **ntfy** on your phone, subscribe to a long random topic, and allow urgent notifications to override Do Not Disturb.
4. `cp infra/terraform.tfvars.example infra/terraform.tfvars` and fill it in (git-ignored). `github_repository` is `OWNER/REPO` of this repo once you push it.
5. Deploy the first time by hand:
   ```sh
   just bootstrap   # state bucket, APIs, image registry
   just image       # builds (linux/amd64) and pushes the container; needs Docker
   just deploy      # everything else (review the plan, type yes)
   just watch       # start the Gmail watch now
   ```

## Hand over to GitHub Actions
Push the repo to GitHub, then:
```sh
just ci-vars     # sets the GCP_WORKLOAD_IDENTITY_PROVIDER and GCP_DEPLOYER_SA repo variables and lets the deployer use the state bucket
gh secret set GOOGLE_CLIENT_ID
gh secret set GOOGLE_CLIENT_SECRET
gh secret set GOOGLE_REFRESH_TOKEN
gh secret set NTFY_TOPIC
```
Auth is keyless (Workload Identity Federation limited to this repository); no JSON keys.
Until `just ci-vars` has set `GCP_WORKLOAD_IDENTITY_PROVIDER`, `infra.yml` skips its jobs and
shows a warning instead of failing. Plans are also skipped on Dependabot PRs, which can't read
Actions secrets.
Optional: in Settings → Environments → `production`, add yourself as a required reviewer to
gate deploys.

**CI follows the justfile.** The workflows only install tools and authenticate; every action
is a `just` recipe, so you can run exactly what CI runs on your laptop.

| workflow | when | runs |
|---|---|---|
| `ci.yml` | every PR and push to `main` | `just lint-rust` (fmt, clippy `-D warnings`, tests), `just lint-docker docker-build` (hadolint + image build), `just lint-infra` (`tofu fmt -check` + `validate`) |
| `infra.yml` → plan | PR touching `infra/`, `ticket-alert/` or the justfile | `just plan`, output posted/updated as a PR comment |
| `infra.yml` → deploy | merge to `main` | `just image` (build + push, tagged with the commit SHA) then `just deploy -auto-approve` |
| dependabot | weekly | Actions, cargo, Docker and provider updates |

Locally: `just lint` = all of `ci.yml` (needs `docker` and `hadolint`: `brew install hadolint`),
`just plan` previews a deploy, `just image deploy` ships one.

Suggested branch protection on `main`: require the three `ci.yml` jobs and the plan job.

## Token rotation (every ~6 days while the app is in Testing)
Google expires the refresh token 7 days after you create it. Put a recurring reminder in your calendar, and:
1. In the OAuth Playground repeat step 5 above (your client ID/secret are still entered; Authorize APIs, Exchange authorization code for tokens) and copy the new refresh token.
2. `just rotate-token` and paste it. This updates the GitHub secret and your local tfvars, then triggers the Infra workflow, which rolls out a new Cloud Run revision with the new token.

If you forget, the service sends an urgent ntfy alert "Gmail auth FAILED" (at most hourly, and the daily watch-renewal job also trips it). Rotate as above; Pub/Sub keeps retrying, so any email that arrived meanwhile is picked up once the new revision is live. Emails received while the token is dead are not alerted until then, so rotate before the event rather than waiting for the alert.

## Day to day
- `just lint` runs the same checks as CI locally; `just fmt` fixes formatting.
- Merge to `main` to deploy, or run `just image deploy` yourself; both use the same recipes.
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
