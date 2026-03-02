# ──────────────────────────────────────────────────────────────
# S3 Remote State — MinIO LXC
# ──────────────────────────────────────────────────────────────
# Prerequisites:
#   1. Deploy MinIO LXC (bootstrap with Ansible first)
#   2. Create bucket: mc mb minio/terraform-state
#   3. Set MINIO_ACCESS_KEY / MINIO_SECRET_KEY or use
#      AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
#
# First run (before MinIO exists):
#   Comment out this backend block and use local state.
#   After MinIO is up, uncomment and run: terraform init -migrate-state
# ──────────────────────────────────────────────────────────────

# terraform {
#   backend "s3" {
#     bucket = "terraform-state"
#     key    = "homelab/terraform.tfstate"
#     region = "us-east-1"            # MinIO ignores this but TF requires it
#
#     endpoints = {
#       s3 = "https://minio.home.arpa:9000"
#     }
#
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#     skip_requesting_account_id  = true
#     use_path_style              = true   # Required for MinIO
#   }
# }
