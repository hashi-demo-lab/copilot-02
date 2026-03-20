data "aws_route53_zone" "this" {
  name         = "${trimsuffix(lower(var.hosted_zone_name), ".")}."
  private_zone = false
}

module "content_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  environment = var.environment
  bucket      = local.content_bucket_name

  is_directory_bucket = false

  attach_policy = true
  policy        = data.aws_iam_policy_document.content_bucket_policy.json

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.common_tags
}

module "access_logs_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  environment = var.environment
  bucket      = local.access_logs_bucket_name

  is_directory_bucket = false

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.common_tags
}

module "acm_certificate" {
  source  = "app.terraform.io/hashi-demos-apj/acm/aws"
  version = "~> 6.1"

  providers = {
    aws = aws.us_east_1
  }

  domain_name               = local.normalized_domain_name
  subject_alternative_names = local.normalized_subject_alternative_names
  validation_method         = "DNS"
  zone_id                   = data.aws_route53_zone.this.zone_id
  wait_for_validation       = true

  tags = local.common_tags
}

module "cloudfront_distribution" {
  source  = "app.terraform.io/hashi-demos-apj/cloudfront/aws"
  version = "~> 5.0"

  aliases             = local.cloudfront_aliases
  comment             = "${local.name_prefix} static content delivery"
  default_root_object = var.default_root_object
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.price_class

  create_monitoring_subscription = false
  create_origin_access_control   = false
  create_origin_access_identity  = true

  origin_access_identities = {
    (local.cloudfront_origin_access_identity_key) = local.cloudfront_origin_access_identity_description
  }

  origin = {
    static = {
      domain_name = module.content_bucket.s3_bucket_bucket_regional_domain_name
      origin_id   = "static-s3-origin"

      s3_origin_config = {
        origin_access_identity = local.cloudfront_origin_access_identity_key
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "static-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    compress               = true
    use_forwarded_values   = false
  }

  logging_config = {
    bucket          = module.access_logs_bucket.s3_bucket_name
    include_cookies = false
    prefix          = "cloudfront/"
  }

  viewer_certificate = {
    acm_certificate_arn      = module.acm_certificate.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = local.common_tags
}
