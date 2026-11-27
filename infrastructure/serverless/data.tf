# DynamoDB single table store.
#
# Cost notes: PAY_PER_REQUEST keeps an idle demo at zero spend, encryption at rest
# is free, and point in time recovery stays off because it is a per-GB charge.

resource "aws_dynamodb_table" "data" {
  name         = "${local.name_prefix}-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi1"
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = false

  tags = {
    Name = "${local.name_prefix}-data"
  }
}
