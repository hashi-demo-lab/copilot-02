provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Project     = var.project_name
    }
  }

  # Dynamic credentials are injected by HCP Terraform.
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Application = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Project     = var.project_name
    }
  }

  # Dynamic credentials are injected by HCP Terraform.
}
