variable "region" {
  type    = string
  default = "us-east-1"
}

variable "source_hostnames" {
  type    = list(string)
  default = ["old.example.com"]
}

variable "target_url" {
  type    = string
  default = "https://new.example.org"
}

module "redirect" {
  source = "../.."

  source_hostnames = var.source_hostnames
  target_url       = var.target_url
}

# Phase 1: create these at your DNS provider so ACM can issue the certificate.
output "certificate_validation_records" {
  value = module.redirect.certificate_validation_records
}

# Phase 2: create these to send traffic to the redirect.
output "redirect_dns_records" {
  value = module.redirect.redirect_dns_records
}
