module "alarm_notifications" {
  source  = "app.terraform.io/hashi-demos-apj/sns/aws"
  version = "~> 7.0"

  name = local.alarm_topic_name

  subscriptions = {
    for endpoint in var.alarm_email_endpoints : endpoint => {
      protocol = "email"
      endpoint = endpoint
    }
  }

  tags = local.common_tags
}

module "cf_4xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  providers = {
    aws = aws.us_east_1
  }

  alarm_name          = local.alarm_4xx_name
  alarm_description   = "CloudFront 4xx error rate exceeded the configured threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_4xx_error_rate_threshold
  dimensions          = local.cloudfront_alarm_dimensions
  alarm_actions       = [module.alarm_notifications.topic_arn]

  tags = local.common_tags
}

module "cf_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  providers = {
    aws = aws.us_east_1
  }

  alarm_name          = local.alarm_5xx_name
  alarm_description   = "CloudFront 5xx error rate exceeded the configured threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_5xx_error_rate_threshold
  dimensions          = local.cloudfront_alarm_dimensions
  alarm_actions       = [module.alarm_notifications.topic_arn]

  tags = local.common_tags
}
