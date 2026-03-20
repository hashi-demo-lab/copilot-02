## Research: AWS architecture best practices for serving static content from an S3 bucket in ap-southeast-2 behind CloudFront with Origin Access Identity and ACM in us-east-1

### Decision
Use the private `hashi-demos-apj` S3, ACM, CloudFront, Route53, CloudWatch, and SNS modules with a primary AWS provider in `ap-southeast-2`, a secondary aliased AWS provider in `us-east-1` for ACM, a private S3 REST origin protected by CloudFront Origin Access Identity, and Route53 alias records pointing to the CloudFront distribution.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/cloudfront/aws` v5.0.1
  - **Purpose**: Creates the CloudFront distribution, Origin Access Identity, viewer certificate attachment, cache behaviors, optional response headers policies, and optional monitoring subscription.
  - **Key Inputs**: `create_origin_access_identity`, `origin_access_identities`, `origin`, `default_cache_behavior`, `viewer_certificate`, `aliases`, `default_root_object`, `price_class`, `create_monitoring_subscription`, `logging_config`, `tags`.
  - **Key Outputs**: `cloudfront_distribution_domain_name` (`string`), `cloudfront_distribution_hosted_zone_id` (`string`), `cloudfront_distribution_id` (`string`), `cloudfront_distribution_arn` (`string`), `cloudfront_origin_access_identity_iam_arns` (`map(string)` inferred from keyed OAI map interface).
  - **Secure Defaults**: Private origin support, OAI support, optional response header policies, optional monitoring subscription; however the consumer should explicitly override viewer TLS settings for a custom domain instead of relying on legacy defaults.
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 — private content bucket in `ap-southeast-2`; exposes `s3_bucket_bucket_regional_domain_name` (`string`) for CloudFront origin wiring and supports public-access blocking, ownership controls, TLS-deny policy, and server-side encryption.
  - `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1 — ACM certificate in `us-east-1`; exposes `acm_certificate_arn` (`string`) for CloudFront `viewer_certificate.acm_certificate_arn` and can manage Route53 DNS validation.
  - `app.terraform.io/hashi-demos-apj/route53/aws` v6.1.1 — public hosted zone and alias record management; use for `A`/`AAAA` aliases targeting `cloudfront_distribution_domain_name` + `cloudfront_distribution_hosted_zone_id`.
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` via the private CloudWatch module repo v5.7.2 — recommended for CloudFront metric alarms.
  - `app.terraform.io/hashi-demos-apj/sns/aws` v7.0.0 — low-friction notification target for CloudWatch alarm actions.
- **Glue Resources Needed**: No raw glue resources are required; use `data "aws_iam_policy_document"` to build the S3 bucket policy that grants `s3:GetObject` only to the CloudFront OAI IAM ARN and optionally denies insecure transport.
- **Wiring Considerations**:
  - Use `module.s3_bucket.s3_bucket_bucket_regional_domain_name` (`string`) as the CloudFront origin `domain_name`; do **not** use the S3 website endpoint because OAI only protects the S3 REST endpoint.
  - Use `module.acm.acm_certificate_arn` (`string`) in `module.cloudfront.viewer_certificate.acm_certificate_arn`; the certificate must be created with an aliased AWS provider in `us-east-1`.
  - Use `module.cloudfront.cloudfront_origin_access_identity_iam_arns["s3"]` (`string`, from `map(string)`) as the principal in the S3 bucket policy; the provider docs recommend the IAM ARN form over the canonical user to avoid spurious diffs.
  - Use `module.cloudfront.cloudfront_distribution_domain_name` (`string`) and `module.cloudfront.cloudfront_distribution_hosted_zone_id` (`string`) for Route53 alias `A` and `AAAA` records.
  - Use `module.cloudfront.cloudfront_distribution_id` (`string`) as the CloudWatch alarm dimension value for CloudFront distribution metrics, with `module.sns.topic_arn` (`string`) as the alarm action.

### Rationale

#### Architecture and service wiring
This stack does not need a VPC. S3, CloudFront, ACM, Route53, CloudWatch, and SNS are all public AWS control-plane services, so introducing a default VPC adds cost and attack surface without adding value for a static-site delivery path. The best-practice implication is to avoid any dependency on default VPC, default subnets, or default security groups; there is no NAT, load balancer, or interface endpoint requirement for the baseline pattern.

For the origin, the S3 bucket should stay private and CloudFront should point at the bucket's **regional REST endpoint** (`s3_bucket_bucket_regional_domain_name`) rather than `website_endpoint`. This matches the S3 module output guidance and avoids CloudFront-to-S3 redirect behavior. It also preserves private-bucket enforcement, which is incompatible with the public S3 website endpoint pattern.

#### Cross-region provider considerations
The bucket should live in `ap-southeast-2`, but the ACM certificate for a CloudFront custom domain must be created in `us-east-1`. The clean consumer pattern is therefore:

```hcl
provider "aws" {
  region = var.aws_region # ap-southeast-2
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

Then pass `providers = { aws = aws.us_east_1 }` to the ACM module, while keeping the S3 bucket on the primary provider. Route53 can stay on the primary provider because it is global, and CloudFront can also be managed from the primary provider, but any future CloudFront-scope WAF configuration should be treated like ACM and managed with a `us-east-1` alias for consistency.

#### Development-cost defaults
For a development or low-risk sandbox deployment, the most cost-conscious defaults are:

- **S3 encryption**: prefer SSE-S3/AES256 rather than SSE-KMS unless there is a compliance requirement for customer-managed keys; this avoids KMS request and key charges.
- **CloudFront price class**: default to `PriceClass_100` for internal/dev testing where global latency is not critical; move to `PriceClass_200` or `PriceClass_All` if APAC user latency matters during testing.
- **No VPC**: do not create or use a default VPC, NAT gateway, or related network modules.
- **Minimal logging by default**: enable CloudFront standard logs only when the environment needs auditability or troubleshooting; keep real-time metrics/monitoring subscription off unless the team needs the extra CloudWatch metrics and accepts the incremental cost.
- **No website hosting mode on S3**: avoid the `website` input for the content bucket; using the REST endpoint behind CloudFront is both cheaper operationally and more secure than maintaining a public website endpoint.

#### Monitoring and alarm recommendations
Recommended baseline monitoring for this pattern:

1. **CloudFront `5xxErrorRate` alarm** — primary availability signal; route to SNS.
2. **CloudFront `4xxErrorRate` alarm** — catches OAI/bucket-policy mistakes, bad cache behaviors, or missing objects; route to SNS with a slightly higher threshold to avoid noisy client-side false positives.
3. **CloudFront `Requests` or traffic-drop alarm** — optional in environments with predictable traffic; otherwise defer to dashboards.
4. **CloudFront additional metrics** — only enable `create_monitoring_subscription = true` if the team needs the extra CloudWatch metrics; it is useful for deeper visibility but is not the cheapest default for dev.
5. **Access logging** — if enabled, send CloudFront standard logs to a **separate private log bucket**, not the content bucket.

A practical minimal alarm set is one SNS topic plus two CloudWatch metric alarms on CloudFront (`5xxErrorRate`, `4xxErrorRate`). If alias records are created, also monitor certificate renewal status operationally because a bad DNS validation flow will surface first as certificate problems, not origin problems.

#### Security controls
Recommended security controls for the baseline design:

- **Private S3 bucket only**: keep S3 Block Public Access enabled (`block_public_acls`, `ignore_public_acls`, `block_public_policy`, `restrict_public_buckets`).
- **Bucket ownership controls**: use `BucketOwnerEnforced` object ownership so ACLs are effectively disabled.
- **Least-privilege bucket policy**: grant only `s3:GetObject` on `${bucket_arn}/*` to the CloudFront OAI IAM ARN; do not make the bucket public.
- **TLS enforcement**: enable a deny-insecure-transport bucket policy on the bucket and set CloudFront `viewer_protocol_policy = "redirect-to-https"`.
- **Viewer certificate hardening**: explicitly set `ssl_support_method = "sni-only"` and `minimum_protocol_version` to a modern TLS policy (`TLSv1.2_2021` minimum; use newer if the private module version supports it). The private CloudFront module documentation shows an older default, so this must be set explicitly.
- **Security headers**: if the CloudFront module response headers policy capability is used, add HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, and XSS protection headers at the edge.
- **Logging separation**: store CloudFront logs in a dedicated private log bucket with log-delivery policy instead of mixing logs with site content.
- **No default VPC reliance**: there should be no ingress path from a VPC or public compute tier to the origin; this architecture is edge-to-S3 only.

#### OAI vs OAC note
The private CloudFront module supports both Origin Access Identity and Origin Access Control. For this feature, OAI is the correct choice because it is an explicit requirement and the private module exposes the OAI IAM ARN needed for a bucket policy. However, for a future revision, OAC is the stronger long-term option AWS is steering new S3 origins toward because it uses SigV4 signing and is the newer access model.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public S3 website endpoint behind CloudFront | Does not satisfy private-origin/OAI requirement; S3 website endpoints are public and cannot be protected with OAI. |
| Direct public S3 bucket without CloudFront | Fails the CDN, TLS-at-edge, custom-domain, and origin-restriction requirements. |
| Origin Access Control instead of Origin Access Identity | Better long-term pattern, but rejected here because the requirement explicitly calls for OAI. |
| Using a default VPC or adding networking modules | No functional benefit for this static-content path; only adds cost, complexity, and unnecessary security surface. |
| ACM certificate in `ap-southeast-2` | CloudFront viewer certificates for custom domains must be in `us-east-1`. |

### Sources

- Private registry: `hashi-demos-apj/cloudfront/aws` v5.0.1 module details and README
- Private registry: `hashi-demos-apj/s3-bucket/aws` v6.0.0 module details and README
- Private registry: `hashi-demos-apj/acm/aws` v6.1.1 module details and README
- Private registry: `hashi-demos-apj/route53/aws` v6.1.1 module details and README
- Private registry: `hashi-demos-apj/cloudwatch/aws` v5.7.2 README examples for `//modules/metric-alarm`
- Private registry: `hashi-demos-apj/sns/aws` v7.0.0 module details and README
- Terraform public module docs: `terraform-aws-modules/cloudfront/aws` v6.4.0
- Terraform public module docs: `terraform-aws-modules/s3-bucket/aws` v5.11.0
- Terraform public module docs: `terraform-aws-modules/acm/aws` v6.3.0
- Terraform provider docs: `aws_cloudfront_distribution` (`viewer_certificate.acm_certificate_arn` must be in `us-east-1`)
- Terraform provider docs: `aws_cloudfront_origin_access_identity` (use `iam_arn` in the S3 bucket policy to avoid spurious diffs)
- Terraform provider docs: `aws_cloudfront_origin_access_control`
- Terraform provider docs: `aws_cloudfront_monitoring_subscription`
- Terraform provider docs: `aws_acm_certificate`
- Terraform provider docs: `aws_s3_bucket_policy`
