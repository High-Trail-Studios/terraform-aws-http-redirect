terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# Any region works. The module pins its certificate to us-east-1 itself, and
# CloudFront and Route 53 are global.
provider "aws" {
  region = var.region
}
