terraform {
  # 1.7 is the first release with mock providers, which the unit tests rely on.
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x is required for the per-resource `region` argument, which lets the
      # ACM certificate live in us-east-1 regardless of the caller's provider.
      version = ">= 6.0, < 7.0"
    }
  }
}
