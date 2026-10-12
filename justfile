# Single source of truth for every action. CI (.github/workflows) only installs tools and
# calls these recipes, so anything CI does you can run locally with the same command.
set shell := ["bash", "-euo", "pipefail", "-c"]

# Override from the environment, e.g. `REGION=europe-west1 just image` (CI sets TAG to the commit SHA)
project := env("PROJECT", "ticket-notifier-511415")
region  := env("REGION", "europe-west4")
tag     := env("TAG", `git rev-parse --short HEAD 2>/dev/null || date +%s`)
image   := region + "-docker.pkg.dev/" + project + "/ticket-alert/ticket-alert:" + tag

# list recipes
default:
    @just --list

# ---------------------------------------------------------------- checks

# format everything
fmt:
    cd ticket-alert && cargo fmt
    tofu fmt -recursive infra

# rust: formatting, clippy (warnings are errors), tests
lint-rust:
    cd ticket-alert && cargo fmt --check
    cd ticket-alert && cargo clippy --locked --all-targets -- -D warnings
    cd ticket-alert && cargo test --locked

# opentofu: formatting + validate (no cloud access needed)
lint-infra:
    tofu fmt -check -recursive -diff infra
    tofu -chdir=infra init -backend=false -input=false
    tofu -chdir=infra validate

# dockerfile lint (needs hadolint: `brew install hadolint`)
lint-docker:
    hadolint --failure-threshold error ticket-alert/Dockerfile

# build the image without pushing
docker-build:
    docker build -t ticket-alert:local ticket-alert

# everything CI checks on a pull request
lint: lint-rust lint-infra lint-docker docker-build

# run the Rust unit tests only
test:
    cd ticket-alert && cargo test

# ---------------------------------------------------------------- deploy

# one-time: state bucket, bootstrap APIs, init OpenTofu, create APIs + image registry
bootstrap:
    gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project {{project}}
    gcloud storage buckets describe gs://{{project}}-tfstate --project {{project}} >/dev/null 2>&1 || gcloud storage buckets create gs://{{project}}-tfstate --project {{project}} --location {{region}} --uniform-bucket-level-access
    gcloud storage buckets update gs://{{project}}-tfstate --versioning --project {{project}}
    tofu -chdir=infra init -input=false
    tofu -chdir=infra apply -target=google_project_service.apis -target=google_artifact_registry_repository.images

# init against the remote state (needs gcloud / CI credentials)
init:
    tofu -chdir=infra init -input=false

# build (linux/amd64, what Cloud Run runs) and push the image for the current tag
image:
    gcloud auth configure-docker {{region}}-docker.pkg.dev --quiet
    docker buildx build --platform linux/amd64 -t {{image}} --push ticket-alert

# show what a deploy would change; also saved to infra/plan.txt (CI posts it on the PR)
plan: init
    tofu -chdir=infra plan -no-color -lock-timeout=120s -var image_tag={{tag}} 2>&1 | tee infra/plan.txt

# apply all infra for the current tag. CI runs: just deploy -auto-approve
deploy *args: init
    tofu -chdir=infra apply -lock-timeout=300s -var image_tag={{tag}} {{args}}

# after the first deploy: point GitHub Actions at the deployer identity (needs `gh` logged in)
ci-vars:
    gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(tofu -chdir=infra output -raw github_workload_identity_provider)"
    gh variable set GCP_DEPLOYER_SA --body "$(tofu -chdir=infra output -raw github_deployer_service_account)"

# ---------------------------------------------------------------- operate

# start the Gmail watch right now (the scheduler also renews it daily)
watch:
    gcloud scheduler jobs run renew-gmail-watch --location {{region}} --project {{project}}

# tail the service logs
logs:
    gcloud run services logs read ticket-alert --region {{region}} --project {{project}} --limit 50

# tear everything down
destroy:
    tofu -chdir=infra destroy
