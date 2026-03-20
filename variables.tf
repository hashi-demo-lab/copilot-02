variable "alarm_4xx_error_rate_threshold" {
  description = "Percentage threshold that triggers the CloudFront 4xxErrorRate alarm."
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_4xx_error_rate_threshold > 0 && var.alarm_4xx_error_rate_threshold <= 100
    error_message = "alarm_4xx_error_rate_threshold must be greater than 0 and less than or equal to 100."
  }
}

variable "alarm_5xx_error_rate_threshold" {
  description = "Percentage threshold that triggers the CloudFront 5xxErrorRate alarm."
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_5xx_error_rate_threshold > 0 && var.alarm_5xx_error_rate_threshold <= 100
    error_message = "alarm_5xx_error_rate_threshold must be greater than 0 and less than or equal to 100."
  }
}

variable "alarm_email_endpoints" {
  description = "Email subscription endpoints attached to the shared SNS alarm topic."
  type        = list(string)

  validation {
    condition = length(var.alarm_email_endpoints) > 0 && alltrue([
      for endpoint in var.alarm_email_endpoints : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", endpoint))
    ])
    error_message = "alarm_email_endpoints must contain at least one syntactically valid email address."
  }
}

variable "aws_region" {
  description = "Primary AWS region for the origin bucket and default provider."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "aws_region must be ap-southeast-2."
  }
}

variable "default_root_object" {
  description = "Default object returned by CloudFront when a directory path is requested."
  type        = string
  default     = "index.html"

  validation {
    condition     = trimspace(var.default_root_object) != "" && !startswith(var.default_root_object, "/")
    error_message = "default_root_object must not be empty and must not start with '/'."
  }
}

variable "domain_name" {
  description = "Primary custom domain name attached to CloudFront and ACM."
  type        = string

  validation {
    condition     = can(regex("^(?i:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+)\\.?$", var.domain_name))
    error_message = "domain_name must be a valid fully qualified domain name."
  }

  validation {
    condition = trimsuffix(lower(var.domain_name), ".") == trimsuffix(lower(var.hosted_zone_name), ".") || endswith(
      trimsuffix(lower(var.domain_name), "."),
      ".${trimsuffix(lower(var.hosted_zone_name), ".")}",
    )
    error_message = "domain_name must be the hosted zone name or a delegated subdomain of hosted_zone_name."
  }
}

variable "environment" {
  description = "Environment tag and naming discriminator for this consumer deployment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.environment)
    error_message = "environment must be one of dev, test, stage, or prod."
  }
}

variable "hosted_zone_name" {
  description = "Existing public DNS zone used for ACM validation and CloudFront alias records."
  type        = string

  validation {
    condition     = can(regex("^(?i:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+)\\.?$", var.hosted_zone_name))
    error_message = "hosted_zone_name must be a valid public hosted zone name."
  }
}

variable "owner" {
  description = "Ownership tag used for accountability and operational routing."
  type        = string

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must be a non-empty team or owner identifier."
  }
}

variable "price_class" {
  description = "CloudFront price class, defaulted for development cost control."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "project_name" {
  description = "Project tag and resource naming prefix for all modules."
  type        = string
  default     = "cloudfront-static-content"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must match ^[a-z0-9-]+$."
  }
}

variable "subject_alternative_names" {
  description = "Additional DNS names included on the ACM certificate and published as aliases."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for name in var.subject_alternative_names : can(regex("^(?i:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+)\\.?$", name))
    ])
    error_message = "Each subject_alternative_names entry must be a valid fully qualified domain name."
  }

  validation {
    condition = alltrue([
      for name in var.subject_alternative_names : trimsuffix(lower(name), ".") == trimsuffix(lower(var.hosted_zone_name), ".") || endswith(
        trimsuffix(lower(name), "."),
        ".${trimsuffix(lower(var.hosted_zone_name), ".")}",
      )
    ])
    error_message = "Each subject_alternative_names entry must be within hosted_zone_name."
  }
}
