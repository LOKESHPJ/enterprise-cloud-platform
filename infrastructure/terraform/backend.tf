# Partial backend configuration. CI supplies the bucket and lock table:
#   terraform init -backend-config="bucket=..." -backend-config="dynamodb_table=..."
terraform {
  backend "s3" {
    key     = "enterprise/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
