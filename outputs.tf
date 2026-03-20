output "access_logs_bucket_name" {
  description = "Name of the private S3 bucket that stores CloudFront standard access logs."
  value       = module.access_logs_bucket.s3_bucket_name
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate attached to the distribution."
  value       = module.acm_certificate.acm_certificate_arn
}

output "alarm_topic_arn" {
  description = "SNS topic ARN that receives CloudFront alarm notifications."
  value       = module.alarm_notifications.topic_arn
}

output "cloudfront_distribution_domain_name" {
  description = "Default CloudFront domain name for validation and troubleshooting."
  value       = module.cloudfront_distribution.cloudfront_distribution_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution identifier used for operations and monitoring."
  value       = module.cloudfront_distribution.cloudfront_distribution_id
}

output "content_bucket_name" {
  description = "Name of the private S3 bucket that stores site content."
  value       = module.content_bucket.s3_bucket_name
}
