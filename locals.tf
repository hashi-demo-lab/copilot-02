locals {
  normalized_domain_name = trimsuffix(lower(var.domain_name), ".")
  domain_name_token      = replace(local.normalized_domain_name, ".", "-")
  name_prefix            = "${var.project_name}-${var.environment}"
  bucket_name_suffix     = substr(md5(local.normalized_domain_name), 0, 8)

  content_bucket_name     = "cfs-${var.environment}-${local.bucket_name_suffix}-content"
  access_logs_bucket_name = "cfs-${var.environment}-${local.bucket_name_suffix}-logs"
  alarm_topic_name        = "${local.name_prefix}-cloudfront-alarms"
  alarm_4xx_name          = "${local.name_prefix}-cloudfront-4xx-error-rate"
  alarm_5xx_name          = "${local.name_prefix}-cloudfront-5xx-error-rate"

  cloudfront_origin_access_identity_key         = "static"
  cloudfront_origin_access_identity_description = "CloudFront access to ${local.content_bucket_name}"

  common_tags = {
    Application = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    Project     = var.project_name
  }

  normalized_subject_alternative_names = [
    for name in var.subject_alternative_names : trimsuffix(lower(name), ".")
  ]

  cloudfront_aliases = distinct(concat(
    [local.normalized_domain_name],
    local.normalized_subject_alternative_names,
  ))

  cloudfront_alias_record_types = [
    "A",
    "AAAA",
  ]

  cloudfront_alias_records = flatten([
    for alias_name in local.cloudfront_aliases : [
      for record_type in local.cloudfront_alias_record_types : {
        name = alias_name
        type = record_type
      }
    ]
  ])

  cloudfront_alarm_dimensions = {
    DistributionId = module.cloudfront_distribution.cloudfront_distribution_id
    Region         = "Global"
  }

  content_bucket_object_arn = "arn:aws:s3:::${local.content_bucket_name}/*"

  content_bucket_policy_principal_arns = module.cloudfront_distribution.cloudfront_origin_access_identity_iam_arns
}
