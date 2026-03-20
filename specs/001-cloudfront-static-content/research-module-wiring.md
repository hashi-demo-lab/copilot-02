## Research: Research module wiring patterns for composing private Terraform modules for S3 static content, CloudFront with OAI, ACM certificate, and CloudWatch alarms

### Decision

Compose `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0, `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1, `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1, and `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` v5.7.2; wire the S3 REST endpoint and bucket ARN into CloudFront and the S3 bucket policy, ACM certificate ARN into `viewer_certificate`, and CloudFront distribution ID into CloudWatch alarms in `us-east-1`.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1
  - **Purpose**: Creates the CloudFront distribution, origin access identity, cache behaviors, viewer certificate binding, and optional CloudFront monitoring subscription.
  - **Key Inputs**:
    - `create_origin_access_identity = true`
    - `origin_access_identities = map(string)`
    - `origin = any`
    - `default_cache_behavior = any`
    - `aliases = list(string)`
    - `viewer_certificate = any`
    - `create_monitoring_subscription = bool`
  - **Key Outputs**:
    - `cloudfront_distribution_id` = `string`
    - `cloudfront_distribution_arn` = `string`
    - `cloudfront_distribution_domain_name` = `string`
    - `cloudfront_distribution_hosted_zone_id` = `string`
    - `cloudfront_origin_access_identity_iam_arns` = `list(string)`
    - `cloudfront_origin_access_identity_ids` = `list(string)`
  - **Secure Defaults**: Distribution creation enabled by default, but OAI, logging, and monitoring are opt-in; consumer should explicitly set HTTPS-only/redirect cache behavior and a stronger TLS policy because module default `viewer_certificate` uses the default CloudFront cert with `minimum_protocol_version = "TLSv1"`.
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — private S3 bucket for static objects; exposes the regional REST endpoint and bucket ARN needed by CloudFront and policy wiring.
  - `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1 — ACM certificate for the CloudFront alias name; exposes `acm_certificate_arn` for CloudFront.
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` v5.7.2 — CloudWatch alarm submodule for CloudFront metrics; accepts `dimensions` and emits alarm identifiers.
- **Glue Resources Needed**: No raw Terraform resources are required for the core composition. Use a `data "aws_iam_policy_document"` data source, or `jsonencode()` on a local object, to produce the S3 bucket policy JSON passed into the S3 module. Use `bucket_prefix` instead of `random_id` if unique bucket naming is required.
- **Wiring Considerations**:
  - **S3 → CloudFront origin**: Use `module.s3_content.s3_bucket_bucket_regional_domain_name` (`string`) as `module.cloudfront.origin["static"].domain_name`. This is the S3 REST endpoint and is the correct endpoint for OAI. Do **not** use `s3_bucket_website_endpoint`/`website` hosting with OAI because website endpoints are public-only and incompatible with private origin access.
  - **OAI keying inside CloudFront module**: The CloudFront module internally resolves OAI paths by matching the key used in `origin_access_identities` to the key referenced in `origin[...].s3_origin_config.origin_access_identity`. Example pattern:
    - `origin_access_identities = { static = "CloudFront access to static bucket" }`
    - `origin = { static = { domain_name = module.s3_content.s3_bucket_bucket_regional_domain_name, s3_origin_config = { origin_access_identity = "static" } } }`
    - This is key-based internal wiring, not a cross-module output transformation.
  - **CloudFront → S3 bucket policy**: Use `module.cloudfront.cloudfront_origin_access_identity_iam_arns` (`list(string)`) directly as the principal identifiers in the generated bucket policy document, and pass that JSON to the S3 module with `attach_policy = true` and `policy = data.aws_iam_policy_document.static_bucket.json`. For object access, transform the bucket ARN string into an object ARN string via interpolation: `"${module.s3_content.s3_bucket_arn}/*"`.
  - **ACM → CloudFront**: Use `module.acm.acm_certificate_arn` (`string`) directly in `module.cloudfront.viewer_certificate.acm_certificate_arn`, with `ssl_support_method = "sni-only"` and an explicit stronger minimum TLS version such as `TLSv1.2_2021`.
  - **CloudFront → CloudWatch alarms**: Use `module.cloudfront.cloudfront_distribution_id` (`string`) in alarm `dimensions = { DistributionId = module.cloudfront.cloudfront_distribution_id, Region = "Global" }`. This is a direct string-to-map entry transformation.
  - **Provider/region split**:
    - Default AWS provider should remain `ap-southeast-2` for the S3 bucket and most deployment context.
    - The ACM private module already exposes `region`; its implementation sets `region = var.region` on `aws_acm_certificate` and `aws_acm_certificate_validation`, so a provider alias is **not strictly required** for same-account DNS validation. Set `region = "us-east-1"` on the ACM module.
    - CloudWatch alarms for CloudFront metrics should use an `aws.us_east_1` provider alias because CloudFront metrics live in `us-east-1`/`Global` for alarming purposes, and the metric-alarm submodule does not expose a `region` input.
    - A provider alias is still appropriate if organization standards prefer explicit region separation or if Route53 validation happens in a different account.
  - **Secure-default preservation**:
    - Keep S3 public access block defaults intact: `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true`.
    - Keep `control_object_ownership = true` and `object_ownership = "BucketOwnerEnforced"`; OAI access is granted via bucket policy, so ACLs do not need to be relaxed.
    - Enable bucket encryption explicitly through `server_side_encryption_configuration` because the module exposes the capability but does not enforce it by default.
    - Prefer CloudFront `viewer_protocol_policy = "redirect-to-https"` and managed cache/origin request policies instead of permissive forwarded values.

### Rationale

The private registry contains all required modules in the `hashi-demos-apj` organization: `s3-bucket`, `cloudfront`, `acm`, and `cloudwatch`. Their interfaces align cleanly for consumer composition.

Verified cross-module output and input compatibility:

- `module.s3_content.s3_bucket_bucket_regional_domain_name` is a `string` output from the S3 module and matches the `domain_name` field used inside the CloudFront `origin` object.
- `module.s3_content.s3_bucket_arn` is a `string` output from the S3 module and can be transformed to the object-resource ARN pattern CloudFront needs in the S3 policy document by appending `/*`.
- `module.acm.acm_certificate_arn` is a `string` output from the ACM module and feeds directly into `viewer_certificate.acm_certificate_arn`.
- `module.cloudfront.cloudfront_origin_access_identity_iam_arns` is a `list(string)` output from the CloudFront module and matches the `identifiers` field of an IAM policy principal block without type coercion.
- `module.cloudfront.cloudfront_distribution_id` is a `string` output from the CloudFront module and fits directly into the CloudWatch alarm `dimensions` map.

The ACM module is notably easier to compose than older public examples suggest. The module README still shows alias-provider patterns for CloudFront and split-provider DNS validation, but the current private module implementation also exposes a `region` input and applies it directly on ACM resources. That means same-account validation can stay module-first and avoid extra provider indirection: keep the root/default provider in `ap-southeast-2`, set `module.acm.region = "us-east-1"`, and only use a provider alias where the consumer genuinely needs a different region-bound service module, such as CloudWatch alarms for CloudFront metrics.

For the S3 side, the safest composition is a private bucket behind CloudFront using the S3 REST endpoint, not the S3 website endpoint. This preserves the S3 module's restrictive public-access defaults and allows CloudFront OAI access to be expressed as module input data rather than a raw `aws_s3_bucket_policy` resource. The only glue needed is policy JSON generation, which can remain in a data source or local expression.

For alarms, the CloudWatch private module is best consumed via its `//modules/metric-alarm` submodule path. This keeps alarm creation module-first and avoids raw `aws_cloudwatch_metric_alarm` resources. The key wiring is simply the CloudFront distribution ID plus the required CloudFront dimensions, with notification actions passed as `list(string)` ARNs from either variables or another approved module.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Use S3 website hosting (`website` output/endpoint) as the CloudFront origin | Incompatible with private OAI access; S3 website endpoints require public access and would defeat the secure-default posture. |
| Use raw `aws_s3_bucket_policy` and `aws_cloudwatch_metric_alarm` resources in consumer code | Violates the consumer constitution's module-first rule; both concerns can be handled with module inputs/submodule usage plus policy-document glue. |
| Put every module on a single `us-east-1` provider | Unnecessarily relocates the S3 bucket away from the requested `ap-southeast-2` region and makes the configuration less explicit about regional intent. |
| Require provider aliases for ACM in all cases | Not necessary with the current private ACM module because it exposes a `region` input and applies it directly on ACM resources; alias providers are only needed for cross-account or organization-standard separation. |
| Prefer CloudFront OAC instead of OAI | OAC is the newer AWS-recommended model and the module supports it, but the requested topology explicitly called for OAI. If requirements loosen later, OAC should be reconsidered because it supports tighter `aws:SourceArn` scoping. |

### Sources

- Private registry module listing, `hashi-demos-apj` organization:
  - `hashi-demos-apj/s3-bucket/aws`
  - `hashi-demos-apj/cloudfront/aws`
  - `hashi-demos-apj/acm/aws`
  - `hashi-demos-apj/cloudwatch/aws`
- Private module details retrieved from HCP Terraform registry:
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
  - `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1
  - `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` v5.7.2
- Source repositories backing the private modules:
  - `https://github.com/hashi-demo-lab/terraform-aws-s3-bucket` (`outputs.tf`, `variables.tf`)
  - `https://github.com/hashi-demo-lab/terraform-aws-cloudfront` (`main.tf`, `outputs.tf`, `variables.tf`, `examples/complete/main.tf`)
  - `https://github.com/hashi-demo-lab/terraform-aws-acm` (`main.tf`, `outputs.tf`, `variables.tf`, `examples/complete-dns-validation/main.tf`)
  - `https://github.com/hashi-demo-lab/terraform-aws-cloudwatch` (`modules/metric-alarm/variables.tf`, `modules/metric-alarm/outputs.tf`, `examples/lambda-metric-alarm/main.tf`)
