set shell := ["bash", "-euo", "pipefail", "-c"]

# Override any of these from the environment, e.g. `REGION=europe-west1 just image`
project := env("PROJECT", "ticket-notifier-511415")
region  := env("REGION", "europe-west4")
tag     := env("TAG", `git rev-parse --short HEAD 2>/dev/null || date +%s`)
image   := region + "-docker.pkg.dev/" + project + "/ticket-alert/ticket-alert:" + tag

# list recipes
default:
    @just --list

# run the Rust unit tests
test:
    cd ticket-alert && cargo test

# format everything
fmt:
    cd ticket-alert && cargo fmt
    tofu fmt -recursive infra

# run every check CI runs (rust fmt/clippy/test, tofu fmt/validate)
lint:
    cd ticket-alert && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked
    tofu fmt -check -recursive infra
    tofu -chdir=infra init -backend=false -input=false >/dev/null
    tofu -chdir=infra validate

# one-time: state bucket, bootstrap APIs, init OpenTofu, create APIs + image registry
bootstrap:
    gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project {{project}}
    gcloud storage buckets describe gs://{{project}}-tfstate --project {{project}} >/dev/null 2>&1 || gcloud storage buckets create gs://{{project}}-tfstate --project {{project}} --location {{region}} --uniform-bucket-level-access
    gcloud storage buckets update gs://{{project}}-tfstate --versioning --project {{project}}
    tofu -chdir=infra init
    tofu -chdir=infra apply -target=google_project_service.apis -target=google_artifact_registry_repository.images

# build + push the container with Cloud Build
image:
    gcloud builds submit ticket-alert --tag {{image}} --project {{project}}

# apply all infra using the image built for the current tag
deploy:
    tofu -chdir=infra apply -var image_tag={{tag}}

# after the first deploy: point GitHub Actions at the deployer identity (needs `gh` logged in)
ci-vars:
    gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(tofu -chdir=infra output -raw github_workload_identity_provider)"
    gh variable set GCP_DEPLOYER_SA --body "$(tofu -chdir=infra output -raw github_deployer_service_account)"

# start the Gmail watch right now (the scheduler also renews it daily)
watch:
    gcloud scheduler jobs run renew-gmail-watch --location {{region}} --project {{project}}

# tail the service logs
logs:
    gcloud run services logs read ticket-alert --region {{region}} --project {{project}} --limit 50

# tear everything down
destroy:
    tofu -chdir=infra destroy
