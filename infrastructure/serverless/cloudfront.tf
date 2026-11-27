variable "enable_cloudfront" {
  description = <<-EOT
    true  -> S3 (private) + CloudFront with Origin Access Control, HTTPS only.
    false -> S3 static website endpoint, HTTP only.

    New AWS accounts cannot create CloudFront distributions until AWS finishes
    account verification, so the fallback keeps the stack deployable on day one.
    Flip this to true once verification completes to get HTTPS and edge caching.
  EOT
  type        = bool
  default     = true
}
