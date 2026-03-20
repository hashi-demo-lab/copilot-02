# Consumer Design: CloudFront Static Content Consumer

**Branch**: feat/001-cloudfront-static-content
**Date**: 2026-03-20
**Status**: Approved
**Provider**: aws ~> 5.0
**Terraform**: >= 1.14
**HCP Terraform Org**: hashi-demos-apj

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions a secure, cost-conscious static content delivery path for a development-facing web property that serves objects from a regional origin in Australia through a globally distributed CDN with custom-domain TLS, DNS routing, operational alarming, and audit-friendly access logging. It exists to provide a repeatable consumer deployment that publishes static assets privately at origin while exposing a resilient HTTPS endpoint for end users and operators.

**Scope boundary**: Application build and content publishing pipelines, non-static application runtimes, WAF policy design, bespoke IAM policy authoring outside approved module interfaces, and any VPC-based compute or networking stack are out of scope for this consumer deployment.

### Requirements

**Functional requirements** -- what the deployment must provision:

- Provision a static content delivery service that serves objects from a private regional origin in `ap-southeast-2` through a CloudFront distribution.
- Provision edge TLS for a custom domain by issuing and validating a certificate in `us-east-1`.
- Ensure the origin remains private and is readable only through CloudFront by using Origin Access Identity.
- Publish DNS records so the custom domain resolves to the CloudFront distribution.
- Emit CloudWatch-backed operational monitoring with at least baseline alarms for CloudFront client and server error rates.
- Preserve access visibility by storing CloudFront standard access logs separately from site content.
- Execute through the HCP Terraform organization `hashi-demos-apj`, project `sandbox`, and workspace `sandbox_consumer_cloudfrontcopilot-02`.

**Non-functional requirements** -- constraints like compliance, performance, availability, cost:

- Use private registry modules only; do not provision raw infrastructure resources in consumer code.
- Keep the deployment compatible with accounts that retain the default VPC, but do not create or depend on networking modules when the delivery path does not require VPC connectivity.
- Use minimal-cost defaults suitable for development, including constrained CDN price class and managed-service choices that avoid unnecessary regional infrastructure.
- Use remote HCP Terraform execution with inherited dynamic AWS credentials and no static AWS secrets.
- Enforce encryption, HTTPS, least-privilege access, logging, and standard ownership tags across all provisioned resources.
- Keep requirements testable through `terraform validate`, HCP Terraform remote plan/apply, alarm creation, and successful origin protection checks.

---

## 2. Module Selection & Architecture

Research evidence key used in this section:

- **[RP]** `research-private-modules.md`
- **[RW]** `research-module-wiring.md`
- **[RA]** `research-aws-architecture.md`
- **[RH]** `research-workspace-deploy.md`

### Architectural Decisions

**Private edge delivery pattern**: Use a private S3 origin in `ap-southeast-2`, front it with CloudFront, bind a custom-domain ACM certificate from `us-east-1`, and publish DNS aliases for the distribution. *Rationale*: [RP], [RW], and [RA] all confirm clean private-registry composition between S3 regional origin outputs, ACM certificate ARN outputs, and CloudFront viewer-certificate and alias targeting requirements, while [RA] confirms the CloudFront certificate regional constraint. *Rejected*: Public S3 website hosting and direct public S3 delivery because they do not satisfy the private-origin requirement and weaken origin protection.

**Origin protection model**: Use Origin Access Identity for S3 origin access and wire the OAI principal into the origin bucket policy. *Rationale*: [RA] and [RW] both show the CloudFront module supports OAI wiring and that OAI is the explicit feature requirement for this deployment. *Rejected*: Origin Access Control, even though it is a stronger future-facing pattern, because the user explicitly requires OAI for this consumer.

**No networking module composition**: Treat the existing default VPC as an environmental fact only and do not compose VPC, subnet, NAT, or security-group modules. *Rationale*: [RA] concludes the service path is managed edge-to-object-storage only, so adding networking modules would increase cost and attack surface without enabling any required capability. *Rejected*: Default-VPC discovery or attachment patterns because they add unnecessary dependencies to a service that does not require VPC connectivity.

**Development-cost observability baseline**: Enable standard CloudFront metrics, two CloudWatch alarms, SNS notification fan-out, and standard access logging to a dedicated private log bucket, while avoiding optional premium monitoring features. *Rationale*: [RA] recommends a minimal baseline of `4xxErrorRate` and `5xxErrorRate` alarms and notes that real-time monitoring subscriptions add cost that is not required for the requested baseline. [RP] confirms the private CloudWatch registry entry is best consumed through the `metric-alarm` submodule. *Rejected*: Real-time metrics subscription and broader alarm sets because they are not necessary to satisfy the stated development requirements.

**Workspace execution model**: Use a remote HCP Terraform workspace with project-inherited dynamic AWS credentials and no workspace-local static credentials. *Rationale*: [RH] confirms the target workspace settings, remote execution model, inherited `agent_AWS_Dynamic_Creds` variable set, and the requirement to create the named workspace before first deployment. *Rejected*: VCS-driven workspace execution and static credential variables because they conflict with the workspace research and the consumer constitution.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|-----------------|---------|---------|-------------|------------|-------------|
| content_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | Private origin bucket for static assets in `ap-southeast-2` ([RP], [RW], [RA]) | always | `environment`, `bucket`, `server_side_encryption_configuration`, `attach_policy`, `policy`, hardening toggles, `tags` | `s3_bucket_name`, `s3_bucket_arn`, `s3_bucket_bucket_regional_domain_name` |
| access_logs_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | Private bucket dedicated to CloudFront standard access logs ([RP], [RA]) | always | `environment`, `bucket`, `server_side_encryption_configuration`, log-bucket hardening toggles, `tags` | `s3_bucket_name`, `s3_bucket_arn` |
| acm_certificate | app.terraform.io/hashi-demos-apj/acm/aws | ~> 6.1 | Custom-domain ACM certificate issued and validated in `us-east-1` for CloudFront viewer TLS ([RP], [RW], [RA]) | always | `domain_name`, `subject_alternative_names`, `validation_method`, `zone_id` or equivalent DNS validation input, `wait_for_validation`, `tags` | `acm_certificate_arn`, `acm_certificate_status` |
| cloudfront_distribution | app.terraform.io/hashi-demos-apj/cloudfront/aws | ~> 5.0 | Global CDN distribution using the private S3 origin, OAI, HTTPS redirection, and access logging ([RP], [RW], [RA]) | always | `origin_access_identities`, `origin`, `default_cache_behavior`, `viewer_certificate`, `aliases`, `default_root_object`, `price_class`, `logging_config`, `tags` | `cloudfront_distribution_id`, `cloudfront_distribution_arn`, `cloudfront_distribution_domain_name`, `cloudfront_distribution_hosted_zone_id`, `cloudfront_origin_access_identity_iam_arns` |
| dns_records | app.terraform.io/hashi-demos-apj/route53/aws | ~> 6.1 | Public DNS alias records for the site domain that target the CloudFront distribution ([RA]) | always | hosted zone selector, alias record definitions, `tags` | alias record FQDNs |
| alarm_notifications | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 | Shared SNS topic for CloudFront alarm notifications ([RA]) | always | topic name, subscriptions, `tags` | `topic_arn` |
| cf_4xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | Alarm on elevated CloudFront `4xxErrorRate` for client-visible delivery failures ([RP], [RA]) | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `threshold`, `alarm_actions`, `tags` | `cloudwatch_metric_alarm_arn` |
| cf_5xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | Alarm on elevated CloudFront `5xxErrorRate` for edge or origin availability failures ([RP], [RA]) | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `threshold`, `alarm_actions`, `tags` | `cloudwatch_metric_alarm_arn` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| -- | -- | No glue resources are required. Policy JSON is generated with a data source in `data.tf`, which does not violate the module-first rule. | -- |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization from clarified requirements and [RH] |
| Project | sandbox | Target project confirmed in [RH] |
| Workspace | sandbox_consumer_cloudfrontcopilot-02 | Named target workspace; [RH] notes it must be created before first deployment |
| Execution Mode | Remote | Required by constitution and confirmed by [RH] |
| Terraform Version | >= 1.14 | Consumer minimum; [RH] recommends pinning workspace to 1.14.x |
| Variable Sets | `agent_AWS_Dynamic_Creds` | Project-inherited dynamic AWS credentials per [RH] |
| VCS Connection | None | CLI-driven remote execution is the preferred mode per [RH] |
| Auto-Apply | Disabled | Best-practice development safety choice from [RH] |

---

## 3. Module Wiring

### Wiring Diagram

```text
module.content_bucket.s3_bucket_bucket_regional_domain_name ──→ module.cloudfront_distribution.origin.static.domain_name
module.access_logs_bucket.s3_bucket_name                   ──→ module.cloudfront_distribution.logging_config.bucket
module.acm_certificate.acm_certificate_arn                 ──→ module.cloudfront_distribution.viewer_certificate.acm_certificate_arn
module.cloudfront_distribution.cloudfront_origin_access_identity_iam_arns ──→ module.content_bucket.policy
module.cloudfront_distribution.cloudfront_distribution_domain_name ──→ module.dns_records.alias_target_name
module.cloudfront_distribution.cloudfront_distribution_hosted_zone_id ──→ module.dns_records.alias_target_zone_id
module.cloudfront_distribution.cloudfront_distribution_id  ──→ module.cf_4xx_alarm.dimensions.DistributionId
module.cloudfront_distribution.cloudfront_distribution_id  ──→ module.cf_5xx_alarm.dimensions.DistributionId
module.alarm_notifications.topic_arn                       ──→ module.cf_4xx_alarm.alarm_actions
module.alarm_notifications.topic_arn                       ──→ module.cf_5xx_alarm.alarm_actions
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| content_bucket | `s3_bucket_bucket_regional_domain_name` | cloudfront_distribution | `origin.static.domain_name` | string | direct |
| access_logs_bucket | `s3_bucket_name` | cloudfront_distribution | `logging_config.bucket` | string | direct |
| acm_certificate | `acm_certificate_arn` | cloudfront_distribution | `viewer_certificate.acm_certificate_arn` | string | direct |
| cloudfront_distribution | `cloudfront_origin_access_identity_iam_arns` | content_bucket | `policy` | string | `data.aws_iam_policy_document.content_bucket_policy.json` using the OAI IAM ARN and `${module.content_bucket.s3_bucket_arn}/*` |
| cloudfront_distribution | `cloudfront_distribution_domain_name` | dns_records | `records.alias_target_name` | string | direct |
| cloudfront_distribution | `cloudfront_distribution_hosted_zone_id` | dns_records | `records.alias_target_zone_id` | string | direct |
| cloudfront_distribution | `cloudfront_distribution_id` | cf_4xx_alarm | `dimensions.DistributionId` | string | direct into `local.cloudfront_alarm_dimensions` |
| cloudfront_distribution | `cloudfront_distribution_id` | cf_5xx_alarm | `dimensions.DistributionId` | string | direct into `local.cloudfront_alarm_dimensions` |
| alarm_notifications | `topic_arn` | cf_4xx_alarm | `alarm_actions` | list(string) | wrap in single-item list |
| alarm_notifications | `topic_arn` | cf_5xx_alarm | `alarm_actions` | list(string) | wrap in single-item list |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
    }
  }

  # Dynamic credentials are injected by HCP Terraform.
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
    }
  }

  # Dynamic credentials are injected by HCP Terraform.
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| `aws_region` | string | No | `ap-southeast-2` | Must equal `ap-southeast-2` to keep the origin bucket in the required region. | No | Primary AWS region for the origin bucket and default provider. |
| `environment` | string | No | `dev` | Must be one of `dev`, `test`, `stage`, or `prod`. | No | Environment tag and naming discriminator for this consumer deployment. |
| `project_name` | string | No | `cloudfront-static-content` | Must match `^[a-z0-9-]+$` and stay within the organization's naming limits. | No | Project tag and resource naming prefix for all modules. |
| `owner` | string | Yes | -- | Must be a non-empty team or owner identifier. | No | Ownership tag used for accountability and operational routing. |
| `domain_name` | string | Yes | -- | Must be a valid fully qualified domain name for the primary site endpoint. | No | Primary custom domain name attached to CloudFront and ACM. |
| `hosted_zone_name` | string | Yes | -- | Must be a valid public Route53 hosted zone name that can validate the certificate and host aliases. | No | Existing public DNS zone used for ACM validation and CloudFront alias records. |
| `subject_alternative_names` | list(string) | No | `[]` | Every entry must be a valid fully qualified domain name and must belong to the same hosted zone delegation model as `domain_name`. | No | Additional DNS names included on the ACM certificate and published as aliases. |
| `default_root_object` | string | No | `index.html` | Must not start with `/` and must not be empty. | No | Default object returned by CloudFront when a directory path is requested. |
| `price_class` | string | No | `PriceClass_100` | Must be one of `PriceClass_100`, `PriceClass_200`, or `PriceClass_All`. | No | CloudFront price class, defaulted for development cost control. |
| `alarm_email_endpoints` | list(string) | Yes | -- | Must contain at least one syntactically valid email address. | No | Email subscription endpoints attached to the shared SNS alarm topic. |
| `alarm_4xx_error_rate_threshold` | number | No | `5` | Must be greater than `0` and less than or equal to `100`. | No | Percentage threshold that triggers the CloudFront `4xxErrorRate` alarm. |
| `alarm_5xx_error_rate_threshold` | number | No | `1` | Must be greater than `0` and less than or equal to `100`. | No | Percentage threshold that triggers the CloudFront `5xxErrorRate` alarm. |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| `content_bucket_name` | string | `module.content_bucket.s3_bucket_name` | Name of the private S3 bucket that stores site content. |
| `access_logs_bucket_name` | string | `module.access_logs_bucket.s3_bucket_name` | Name of the private S3 bucket that stores CloudFront standard access logs. |
| `cloudfront_distribution_id` | string | `module.cloudfront_distribution.cloudfront_distribution_id` | CloudFront distribution identifier used for operations and monitoring. |
| `cloudfront_distribution_domain_name` | string | `module.cloudfront_distribution.cloudfront_distribution_domain_name` | Default CloudFront domain name for validation and troubleshooting. |
| `acm_certificate_arn` | string | `module.acm_certificate.acm_certificate_arn` | ARN of the ACM certificate attached to the distribution. |
| `alarm_topic_arn` | string | `module.alarm_notifications.topic_arn` | SNS topic ARN that receives CloudFront alarm notifications. |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | The content and access-log buckets both keep data encrypted at rest with explicit SSE-S3 configuration, while ACM stores certificate material in the managed service. This avoids extra KMS cost for development while keeping encrypted storage enabled. | `module.content_bucket`: `server_side_encryption_configuration = AES256`; `module.access_logs_bucket`: `server_side_encryption_configuration = AES256`; `module.acm_certificate`: managed-service default protection | AWS Well-Architected Security Pillar – Data Protection |
| Encryption in transit | Viewer traffic is forced onto HTTPS at the edge, the CloudFront custom certificate is attached from `us-east-1`, modern TLS is required, and both S3 buckets attach deny-insecure-transport and latest-TLS bucket policies. | `module.cloudfront_distribution`: `viewer_certificate.acm_certificate_arn`, `viewer_certificate.ssl_support_method = "sni-only"`, `viewer_certificate.minimum_protocol_version = "TLSv1.2_2021"`, `default_cache_behavior.viewer_protocol_policy = "redirect-to-https"`; `module.content_bucket` and `module.access_logs_bucket`: `attach_deny_insecure_transport_policy = true`, `attach_require_latest_tls_policy = true` | AWS Well-Architected Security Pillar – Data Protection; CIS AWS Foundations Benchmark – secure transport |
| Public access | The S3 buckets retain block-public-access defaults, website hosting stays disabled, and CloudFront is the only public entry point. Origin reads are restricted to the OAI principal instead of broad anonymous access. | `module.content_bucket` and `module.access_logs_bucket`: default `block_public_*` controls and `object_ownership = "BucketOwnerEnforced"`; `module.cloudfront_distribution`: `create_origin_access_identity = true`, S3 REST origin only | AWS Well-Architected Security Pillar – Infrastructure Protection; CIS AWS Foundations Benchmark – S3 public access blocking |
| IAM least privilege | The origin bucket policy grants only `s3:GetObject` on content objects to the CloudFront OAI identity, HCP Terraform supplies temporary provider credentials, and the alarm actions are constrained to a single SNS topic. No static keys or wildcard origin access are introduced. | `module.content_bucket`: `attach_policy = true` with OAI-scoped policy JSON; `module.cloudfront_distribution`: OAI output consumed by policy; `module.alarm_notifications`: single-topic action target; workspace: inherited `agent_AWS_Dynamic_Creds` variable set | AWS Well-Architected Security Pillar – Identity and Access Management |
| Logging | CloudFront standard access logs are delivered to a dedicated private log bucket, and baseline operational visibility is enforced with CloudWatch alarms on `4xxErrorRate` and `5xxErrorRate`. No [SECURITY OVERRIDE] is required because logging is enabled rather than weakened. | `module.access_logs_bucket`: dedicated private log target; `module.cloudfront_distribution`: `logging_config` pointing to the log bucket; `module.cf_4xx_alarm` and `module.cf_5xx_alarm`: `namespace = "AWS/CloudFront"` with distribution-specific dimensions | AWS Well-Architected Security Pillar – Enable Traceability; CIS AWS Foundations Benchmark – logging and monitoring |
| Tagging | Provider `default_tags` guarantee `ManagedBy`, `Environment`, `Project`, and `Owner` across both primary and aliased providers, and all modules inherit or receive the same common tag set for governance and cost attribution. | `provider.aws` and `provider.aws.us_east_1`: `default_tags` include `ManagedBy`, `Environment`, `Project`, `Owner`; all modules: `tags = local.common_tags` | AWS Well-Architected Security Pillar – Automate Security Best Practices |

---

## 5. Implementation Checklist

- [ ] **A: Foundation files** -- Create `versions.tf`, `backend.tf`, `providers.tf`, and `variables.tf` with Terraform/HCP workspace settings, required providers, primary and aliased AWS providers, and all deployment inputs from Section 3.
- [ ] **B: Shared wiring primitives** -- Create `locals.tf` and `data.tf` with naming locals, common tags, CloudFront alarm dimensions, alias record lists, and the IAM policy document that binds the OAI to the content bucket.
- [ ] **C: Core delivery modules** -- Create `main.tf` with the `content_bucket`, `access_logs_bucket`, `acm_certificate`, and `cloudfront_distribution` module calls wired for private origin access, HTTPS, logging, and development-cost defaults.
- [ ] **D: DNS and monitoring modules** -- Create `dns.tf` and `monitoring.tf` with the `dns_records`, `alarm_notifications`, `cf_4xx_alarm`, and `cf_5xx_alarm` module calls, including email subscriptions and CloudFront metric dimensions.
- [ ] **E: Interface and operator documentation** -- Create `outputs.tf`, `README.md`, and `terraform.auto.tfvars.example` with the published outputs, deployment instructions, example input values, and validation workflow for the sandbox workspace.

---

## 6. Open Questions

None.

---
