variable "region" {
  type    = string
  default = "us-east-1"
}

variable "zone_name" {
  description = "A public Route 53 hosted zone you own."
  type        = string
  default     = "example.com"
}

variable "target_url" {
  type    = string
  default = "https://www.example.org"
}

module "redirect" {
  source = "../.."

  source_hostnames  = [var.zone_name, "www.${var.zone_name}"]
  target_url        = var.target_url
  route53_zone_name = var.zone_name
}

output "cloudfront_domain_name" {
  value = module.redirect.cloudfront_domain_name
}
