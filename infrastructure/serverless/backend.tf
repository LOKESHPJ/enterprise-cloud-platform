# Partial backend configuration: bucket and lock table are injected by CI with
#   terraform init -backend-config="bucket=..." -backend-config="dynamodb_table=..."
# so no account specific values are committed to the repository.
terraform {
  backend "s3" {
    key     = "serverless/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
