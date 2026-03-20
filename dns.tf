module "dns_records" {
  source  = "app.terraform.io/hashi-demos-apj/route53/aws"
  version = "~> 6.1"

  create_zone  = false
  name         = data.aws_route53_zone.this.name
  private_zone = false

  records = {
    for record in local.cloudfront_alias_records : "${record.name}-${record.type}" => {
      name = record.name
      type = record.type
      alias = {
        name                   = module.cloudfront_distribution.cloudfront_distribution_domain_name
        zone_id                = module.cloudfront_distribution.cloudfront_distribution_hosted_zone_id
        evaluate_target_health = false
      }
    }
  }

  tags = local.common_tags
}
