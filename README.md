# CloudFront Static Content Consumer

Terraform consumer configuration for a private static-content delivery stack in the HCP Terraform workspace `sandbox_consumer_cloudfrontcopilot-02`.

## Architecture Summary

This configuration composes private registry modules to deploy:

- a private S3 content bucket in `ap-southeast-2`
- a private S3 access-logs bucket
- an ACM certificate in `us-east-1` for the custom domain
- a CloudFront distribution with Origin Access Identity (OAI)
- Route53 alias records for the site domain and any SAN aliases
- SNS-backed CloudWatch alarms for CloudFront `4xxErrorRate` and `5xxErrorRate`

The backend is already bound to:

- organization: `hashi-demos-apj`
- project: `sandbox`
- workspace: `sandbox_consumer_cloudfrontcopilot-02`

## Prerequisites

Before the first run, ensure:

1. The HCP Terraform workspace `sandbox_consumer_cloudfrontcopilot-02` exists in the `sandbox` project.
2. Your CLI is authenticated to HCP Terraform (`terraform login` or `TF_TOKEN_app_terraform_io`).
3. The workspace inherits the `agent_AWS_Dynamic_Creds` variable set.
4. The `hosted_zone_name` value refers to an existing public Route53 hosted zone.
5. The `domain_name` and any `subject_alternative_names` are covered by that hosted zone.

## Example Inputs

Copy the example file and replace the sample values with your delegated sandbox values:

```bash
cp terraform.auto.tfvars.example terraform.auto.tfvars
```

Example values are provided for a non-interactive sandbox run and align with the workspace naming convention:

```hcl
  owner                     = "hashi-demo-lab"
  domain_name               = "cloudfrontcopilot-02.hashidemos.io"
  hosted_zone_name          = "hashidemos.io"
  subject_alternative_names = ["www.cloudfrontcopilot-02.hashidemos.io"]
  alarm_email_endpoints     = ["cloudfrontcopilot-02@hashidemos.io"]
```

## Deployment Instructions

Run the workflow from this directory:

```bash
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan -input=false -out=tfplan
terraform apply -input=false tfplan
```

Notes:

- `terraform init` connects the local working directory to the remote HCP Terraform workspace configured in `backend.tf`.
- `terraform plan` and `terraform apply` execute against the remote backend; no static AWS keys are required in the root configuration.
- DNS validation for ACM and Route53 alias creation depend on the public hosted zone identified by `hosted_zone_name`.

## Sandbox Validation Workflow

Use the following non-interactive workflow for sandbox validation:

1. `terraform init -input=false`
2. `terraform fmt -check`
3. `terraform validate`
4. `terraform plan -input=false -out=tfplan`
5. Review the remote plan in HCP Terraform.
6. `terraform apply -input=false tfplan`
7. Confirm the deployment outputs with `terraform output`.
8. Validate DNS resolution and HTTPS:
   - `terraform output cloudfront_distribution_domain_name`
    - `dig cloudfrontcopilot-02.hashidemos.io`
    - `curl -I https://cloudfrontcopilot-02.hashidemos.io`

If you need to clean up the sandbox deployment:

```bash
terraform destroy -input=false -auto-approve
```

## Published Outputs

The root module publishes these outputs after apply:

- `access_logs_bucket_name`
- `acm_certificate_arn`
- `alarm_topic_arn`
- `cloudfront_distribution_domain_name`
- `cloudfront_distribution_id`
- `content_bucket_name`

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.37.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_access_logs_bucket"></a> [access\_logs\_bucket](#module\_access\_logs\_bucket) | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 |
| <a name="module_acm_certificate"></a> [acm\_certificate](#module\_acm\_certificate) | app.terraform.io/hashi-demos-apj/acm/aws | ~> 6.1 |
| <a name="module_alarm_notifications"></a> [alarm\_notifications](#module\_alarm\_notifications) | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 |
| <a name="module_cf_4xx_alarm"></a> [cf\_4xx\_alarm](#module\_cf\_4xx\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |
| <a name="module_cf_5xx_alarm"></a> [cf\_5xx\_alarm](#module\_cf\_5xx\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |
| <a name="module_cloudfront_distribution"></a> [cloudfront\_distribution](#module\_cloudfront\_distribution) | app.terraform.io/hashi-demos-apj/cloudfront/aws | ~> 5.0 |
| <a name="module_content_bucket"></a> [content\_bucket](#module\_content\_bucket) | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 |
| <a name="module_dns_records"></a> [dns\_records](#module\_dns\_records) | app.terraform.io/hashi-demos-apj/route53/aws | ~> 6.1 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy_document.content_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_4xx_error_rate_threshold"></a> [alarm\_4xx\_error\_rate\_threshold](#input\_alarm\_4xx\_error\_rate\_threshold) | Percentage threshold that triggers the CloudFront 4xxErrorRate alarm. | `number` | `5` | no |
| <a name="input_alarm_5xx_error_rate_threshold"></a> [alarm\_5xx\_error\_rate\_threshold](#input\_alarm\_5xx\_error\_rate\_threshold) | Percentage threshold that triggers the CloudFront 5xxErrorRate alarm. | `number` | `1` | no |
| <a name="input_alarm_email_endpoints"></a> [alarm\_email\_endpoints](#input\_alarm\_email\_endpoints) | Email subscription endpoints attached to the shared SNS alarm topic. | `list(string)` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Primary AWS region for the origin bucket and default provider. | `string` | `"ap-southeast-2"` | no |
| <a name="input_default_root_object"></a> [default\_root\_object](#input\_default\_root\_object) | Default object returned by CloudFront when a directory path is requested. | `string` | `"index.html"` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Primary custom domain name attached to CloudFront and ACM. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag and naming discriminator for this consumer deployment. | `string` | `"dev"` | no |
| <a name="input_hosted_zone_name"></a> [hosted\_zone\_name](#input\_hosted\_zone\_name) | Existing public DNS zone used for ACM validation and CloudFront alias records. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Ownership tag used for accountability and operational routing. | `string` | n/a | yes |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | CloudFront price class, defaulted for development cost control. | `string` | `"PriceClass_100"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project tag and resource naming prefix for all modules. | `string` | `"cloudfront-static-content"` | no |
| <a name="input_subject_alternative_names"></a> [subject\_alternative\_names](#input\_subject\_alternative\_names) | Additional DNS names included on the ACM certificate and published as aliases. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_logs_bucket_name"></a> [access\_logs\_bucket\_name](#output\_access\_logs\_bucket\_name) | Name of the private S3 bucket that stores CloudFront standard access logs. |
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ARN of the ACM certificate attached to the distribution. |
| <a name="output_alarm_topic_arn"></a> [alarm\_topic\_arn](#output\_alarm\_topic\_arn) | SNS topic ARN that receives CloudFront alarm notifications. |
| <a name="output_cloudfront_distribution_domain_name"></a> [cloudfront\_distribution\_domain\_name](#output\_cloudfront\_distribution\_domain\_name) | Default CloudFront domain name for validation and troubleshooting. |
| <a name="output_cloudfront_distribution_id"></a> [cloudfront\_distribution\_id](#output\_cloudfront\_distribution\_id) | CloudFront distribution identifier used for operations and monitoring. |
| <a name="output_content_bucket_name"></a> [content\_bucket\_name](#output\_content\_bucket\_name) | Name of the private S3 bucket that stores site content. |
<!-- END_TF_DOCS -->
