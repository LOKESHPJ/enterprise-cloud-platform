# Static frontend.
#
# Two hosting modes, selected by var.enable_cloudfront:
#   cloudfront = true  -> private bucket, CloudFront + OAC, HTTPS, edge caching
#   cloudfront = false -> S3 website endpoint, HTTP only (unverified accounts)
#
# Both modes share the same bucket; only the read path differs.

resource "aws_s3_bucket" "web" {
  bucket        = "${local.name_prefix}-web-${local.account_id}"
  force_destroy = true

  tags = {
    Name = "${local.name_prefix}-web"
  }
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# CloudFront mode (default): bucket stays private, CloudFront reads via OAC.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "web_private" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "web" {
  count = var.enable_cloudfront ? 1 : 0

  name                              = "${local.name_prefix}-web-oac"
  description                       = "OAC for the ${local.name_prefix} static site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "web_bucket_private" {
  count = var.enable_cloudfront ? 1 : 0

  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web_private" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket_private[0].json

  depends_on = [aws_s3_bucket_public_access_block.web_private]
}

resource "aws_cloudfront_response_headers_policy" "web" {
  count = var.enable_cloudfront ? 1 : 0

  name    = "${local.name_prefix}-security-headers"
  comment = "Baseline browser security headers"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
  }
}

data "aws_cloudfront_cache_policy" "optimized" {
  count = var.enable_cloudfront ? 1 : 0

  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "web" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${local.name_prefix} single page application"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.web.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.web[0].id
  }

  default_cache_behavior {
    target_origin_id           = "s3-${aws_s3_bucket.web.id}"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized[0].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.web[0].id
    compress                   = true
  }

  # SPA routing: let the client side router own unknown paths.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.name_prefix}-cdn"
  }
}

# ---------------------------------------------------------------------------
# S3 website mode: used only while the account is unverified.
# This trades HTTPS for availability; it is not the recommended production path.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "web_public" {
  count = var.enable_cloudfront ? 0 : 1

  bucket = aws_s3_bucket.web.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "web" {
  count = var.enable_cloudfront ? 0 : 1

  bucket = aws_s3_bucket.web.id

  index_document {
    suffix = "index.html"
  }

  # Serves index.html for client side routes, mirroring the CloudFront behaviour.
  error_document {
    key = "index.html"
  }
}

data "aws_iam_policy_document" "web_bucket_public" {
  count = var.enable_cloudfront ? 0 : 1

  statement {
    sid       = "PublicReadForWebsiteEndpoint"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "web_public" {
  count = var.enable_cloudfront ? 0 : 1

  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket_public[0].json

  depends_on = [aws_s3_bucket_public_access_block.web_public]
}
