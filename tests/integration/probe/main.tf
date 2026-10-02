# Test helper: makes one HTTP request without following redirects and reports
# the status code and Location header.

terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3, < 3.0"
    }
  }
}

variable "url" {
  type = string
}

variable "connect_host" {
  description = "Host to connect to in place of the URL's host (the CloudFront domain)."
  type        = string
}

data "external" "probe" {
  program = ["sh", "${path.module}/probe.sh", var.url, var.connect_host]
}
