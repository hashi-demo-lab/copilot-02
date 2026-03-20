## Research: Private registry module availability for a CloudFront static content consumer in HCP Terraform org hashi-demos-apj

### Decision
Use the private `s3-bucket`, `cloudfront`, and `acm` modules from `hashi-demos-apj`, and treat `cloudwatch` as a set of private submodules (primarily `//modules/metric-alarm` and optionally `//modules/log-group`) rather than a single root module, because the first three directly support the S3 + CloudFront + ACM composition while CloudWatch coverage is alarming-oriented and not a complete logging solution for CloudFront access logs.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1
  - **Purpose**: Creates a CloudFront distribution, optional origin access identity/control resources, optional monitoring subscription, and optional VPC origin.
  - **Important Inputs**:
    - `origin` (`any`) - required in practice; for S3-backed static content, set origin `domain_name` from the S3 module's `s3_bucket_bucket_regional_domain_name` output and configure S3 origin settings.
    - `default_cache_behavior` (`any`) - required in practice; set `target_origin_id`, caching behavior, compression, and `viewer_protocol_policy`.
    - `aliases` (`list(string)`) - custom domains/CNAMEs.
    - `viewer_certificate` (`any`) - pass `acm_certificate_arn` from the ACM module for custom domains.
    - `create_origin_access_control` (`bool`) and `origin_access_control` (`map(object(...))`) - recommended for private S3 origins.
    - `logging_config` (`any`) - sends standard access logs to an S3 bucket, not CloudWatch Logs.
    - `create_monitoring_subscription` (`bool`) / `realtime_metrics_subscription_status` (`string`) - enables additional CloudWatch metrics.
  - **Useful Outputs for Downstream Wiring**:
    - `cloudfront_distribution_arn` = `string`
    - `cloudfront_distribution_id` = `string`
    - `cloudfront_distribution_domain_name` = `string`
    - `cloudfront_distribution_hosted_zone_id` = `string`
    - `cloudfront_origin_access_controls_ids` = `list(string)`
    - `cloudfront_origin_access_identity_iam_arns` = `list(string)`
  - **Secure Defaults**:
    - `enabled = true`, `wait_for_deployment = true`.
    - When OAC objects are created, default OAC signing is `sigv4` with `signing_behavior = "always"`.
    - `realtime_metrics_subscription_status = "Enabled"` by default.
  - **Caveats / Gaps**:
    - `create_origin_access_control = false` by default, so recommended private-origin protection is opt-in.
    - Default `viewer_certificate` uses the CloudFront default certificate and `minimum_protocol_version = "TLSv1"`; for a production custom domain, override with ACM ARN and modern TLS policy (for example `TLSv1.2_2021`).
    - Bucket access still needs an S3 bucket policy that permits the CloudFront distribution ARN to read objects.

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
  - **Purpose**: Creates the origin bucket for static content and optional logging bucket if desired.
  - **Important Inputs**:
    - `environment` (`string`, required) - mandatory org-specific input.
    - `bucket` / `bucket_prefix` - bucket naming.
    - `versioning` (`map(string)`) - object versioning.
    - `force_destroy` (`bool`) - destructive cleanup behavior.
    - `logging` (`any`) - S3 server access logging.
    - `server_side_encryption_configuration` (`any`) - SSE configuration.
    - `attach_policy` (`bool`) + `policy` (`string`) - attach custom bucket policy for CloudFront access.
    - `attach_deny_insecure_transport_policy`, `attach_require_latest_tls_policy`, `attach_deny_unencrypted_object_uploads`, `attach_deny_incorrect_encryption_headers`, `attach_deny_incorrect_kms_key_sse` - recommended hardening toggles.
    - `website` (`any`) - available, but for private CloudFront + OAC patterns the better origin is the bucket REST/regional endpoint, not S3 website hosting.
  - **Useful Outputs for Downstream Wiring**:
    - `s3_bucket_name` = `string`
    - `s3_bucket_arn` = `string`
    - `s3_bucket_bucket_domain_name` = `string`
    - `s3_bucket_bucket_regional_domain_name` = `string`
    - `s3_bucket_hosted_zone_id` = `string`
    - `s3_bucket_region` = `string`
    - `s3_bucket_tags` = `map(string)`
    - `aws_s3_bucket_versioning_status` = `string | null`
  - **Secure Defaults**:
    - Public access block defaults are enabled: `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true`.
    - Object ownership defaults to `BucketOwnerEnforced` with `control_object_ownership = true`.
    - `attach_public_policy = true` prevents silently disabling upstream default policy handling.
  - **Caveats / Gaps**:
    - Transport/encryption guardrail bucket policies are mostly opt-in; explicitly enable them for a production static-content bucket.
    - The default `type = "Directory"` is not appropriate for a standard CloudFront S3 origin; keep `is_directory_bucket = false` and use a normal S3 bucket.

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1
  - **Purpose**: Requests and validates ACM certificates, usually via Route53 DNS validation.
  - **Important Inputs**:
    - `domain_name` (`string`) - certificate subject.
    - `subject_alternative_names` (`list(string)`) - SANs such as apex + `www`.
    - `validation_method` (`string`) - use `DNS` for automation.
    - `zone_id` (`string`) or `zones` (`map(string)`) - Route53 hosted zone(s) for validation.
    - `create_route53_records` (`bool`) / `create_route53_records_only` (`bool`) - split-certificate vs split-DNS workflows.
    - `wait_for_validation` (`bool`) - pipeline behavior.
    - `region` (`string`) - important for CloudFront.
  - **Useful Outputs for Downstream Wiring**:
    - `acm_certificate_arn` = `string`
    - `acm_certificate_status` = `string`
    - `validation_route53_record_fqdns` = `list(string)`
    - `distinct_domain_names` = `list(string)`
    - `acm_certificate_domain_validation_options` = `list(object({ domain_name = string, resource_record_name = string, resource_record_type = string, resource_record_value = string }))`
  - **Secure Defaults**:
    - `certificate_transparency_logging_preference = true`.
    - `validate_certificate = true` and `create_route53_records = true` support automated DNS validation by default.
    - `wait_for_validation = true` helps avoid racing CloudFront against an unissued certificate.
  - **Caveats / Gaps**:
    - For CloudFront viewer certificates, the ACM certificate must be requested in `us-east-1`; use provider aliasing or set this module's `region` accordingly.
    - If DNS is managed separately, glue may be needed around `acm_certificate_domain_validation_options` and `validation_route53_record_fqdns`.

- **Supporting Module**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
  - **Purpose**: Private registry entry for CloudWatch submodules rather than a single opinionated root module. Most relevant submodules for this consumer are `//modules/metric-alarm` and, if application-side logging is needed, `//modules/log-group`.
  - **Important Inputs**:
    - `//modules/metric-alarm`: `alarm_name`, `comparison_operator`, `evaluation_periods`, `metric_name`, `namespace`, `period`, `statistic`, `threshold`, optional `dimensions`, and action ARN lists.
    - `//modules/log-group`: `name`, `retention_in_days`, optional `kms_key_id`, optional `skip_destroy`, and tags.
  - **Useful Outputs for Downstream Wiring**:
    - `//modules/metric-alarm`: `cloudwatch_metric_alarm_arn` = `string`, `cloudwatch_metric_alarm_id` = `string`
    - `//modules/log-group`: `cloudwatch_log_group_name` = `string`, `cloudwatch_log_group_arn` = `string`
  - **Secure Defaults**:
    - `create_metric_alarm = true` / `create = true`.
    - `treat_missing_data = "missing"` on the metric alarm submodule.
  - **Caveats / Gaps**:
    - The root private module is not itself a ready-made CloudFront monitoring module; consumers must select submodules.
    - There is no dedicated private module here for CloudFront standard access logs because CloudFront standard logging targets S3, not CloudWatch Logs.
    - If near-real-time request logs are required, additional glue/infrastructure beyond this module set is needed (for example CloudFront real-time logs plus Kinesis consumer resources).

- **Glue Resources Needed**:
  - `data "aws_iam_policy_document"` to generate the S3 bucket policy granting `cloudfront.amazonaws.com` access constrained by `AWS:SourceArn = module.cloudfront.cloudfront_distribution_arn`.
  - Potential separate S3 log bucket (can reuse the same private `s3-bucket` module) if CloudFront standard access logs are enabled through `logging_config`.
  - Potential Route53 resources/module for alias records to `cloudfront_distribution_domain_name` + `cloudfront_distribution_hosted_zone_id` and for ACM DNS validation if DNS is not created within the ACM module.

- **Wiring Considerations**:
  - S3 origin -> CloudFront: use `module.s3_bucket.s3_bucket_bucket_regional_domain_name` (`string`) as the CloudFront origin `domain_name`; this avoids S3 redirect issues.
  - ACM -> CloudFront: use `module.acm.acm_certificate_arn` (`string`) in `viewer_certificate.acm_certificate_arn`; for custom domains the certificate must exist in `us-east-1`.
  - CloudFront -> S3 policy: use `module.cloudfront.cloudfront_distribution_arn` (`string`) in the S3 bucket policy condition.
  - CloudFront -> DNS: use `module.cloudfront.cloudfront_distribution_domain_name` (`string`) and `module.cloudfront.cloudfront_distribution_hosted_zone_id` (`string`) for Route53 alias records.
  - ACM validation split workflow: if DNS records are managed elsewhere, use `module.acm.acm_certificate_domain_validation_options` (`list(object(...))`) or `validation_route53_record_fqdns` (`list(string)`) across module boundaries.
  - CloudFront metrics -> CloudWatch alarms: the CloudWatch private module can alarm on `AWS/CloudFront` metrics using distribution dimensions, but this is a separate composition step from CloudFront logging.

### Rationale

The private registry in `hashi-demos-apj` contains all four named modules: `s3-bucket`, `cloudfront`, `acm`, and `cloudwatch`. The first three are direct private mirrors/customizations of mature `terraform-aws-modules` implementations and expose the interfaces needed for a standard static-site composition: S3 origin endpoint output, ACM certificate ARN output, and CloudFront distribution origin/viewer-certificate inputs plus DNS-friendly outputs. Output types were verified from the underlying module HCL: `s3_bucket_bucket_regional_domain_name`, `acm_certificate_arn`, `cloudfront_distribution_domain_name`, `cloudfront_distribution_hosted_zone_id`, and `cloudfront_distribution_arn` all resolve to scalar strings; the ACM validation handoff output resolves to a list of objects; CloudWatch submodule outputs resolve to scalar strings.

The main design constraint is regional: CloudFront viewer certificates must be issued in `us-east-1`, even if the S3 origin bucket and most other infrastructure live in another AWS region. The second important constraint is access control: for a private S3 origin, the bucket module and CloudFront module do not fully complete the trust relationship on their own; consumers still need a bucket policy referencing the resulting distribution ARN. Finally, the private CloudWatch registry entry is useful, but only as a library of submodules for alarms/log groups; it does not itself provide a single turnkey CloudFront observability module, and CloudFront standard access logging still lands in S3 rather than CloudWatch Logs.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Use S3 website hosting as the CloudFront origin | Works for public website endpoints, but it bypasses the stronger private-origin/OAC pattern and is not the preferred secure design for static content behind CloudFront. |
| Use the CloudFront module without ACM/custom aliases | Suitable only for default `cloudfront.net` domains; does not satisfy a typical branded static-content consumer. |
| Treat the private `cloudwatch` root module as a single drop-in monitoring module | The root module is a container of submodules, not a turnkey CloudFront monitoring abstraction. |
| Skip S3 bucket policy glue and rely only on OAC/OAI creation | CloudFront access to a private S3 origin still requires the bucket policy side of the trust relationship. |

### Sources

- Private registry module listing and details for `hashi-demos-apj/s3-bucket/aws` v6.0.0
- Private registry module listing and details for `hashi-demos-apj/cloudfront/aws` v5.0.1
- Private registry module listing and details for `hashi-demos-apj/acm/aws` v6.1.1
- Private registry module listing and details for `hashi-demos-apj/cloudwatch/aws` v5.7.2
- Underlying module source HCL inspected from:
  - `hashi-demo-lab/terraform-aws-s3-bucket` (`outputs.tf`)
  - `hashi-demo-lab/terraform-aws-cloudfront` (`outputs.tf`)
  - `hashi-demo-lab/terraform-aws-acm` (`outputs.tf`)
  - `hashi-demo-lab/terraform-aws-cloudwatch` (`modules/log-group`, `modules/metric-alarm`)
- Public registry patterns:
  - `terraform-aws-modules/cloudfront/aws` v6.4.0
  - `terraform-aws-modules/s3-bucket/aws` v5.11.0
  - `terraform-aws-modules/acm/aws` v6.3.0
- Terraform AWS provider docs:
  - `aws_cloudfront_distribution`
  - `aws_acm_certificate`
