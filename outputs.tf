output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution that serves the redirect."
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (dxxxx.cloudfront.net) that the source hostnames must point at."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "Route 53 hosted zone ID for CloudFront alias records (the same for every distribution)."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "acm_certificate_arn" {
  description = "ARN of the us-east-1 ACM certificate covering the source hostnames."
  value       = aws_acm_certificate.this.arn
}

output "certificate_validation_records" {
  description = "DNS records that prove ownership to ACM. Created automatically in Route 53 mode; with another DNS provider, create these yourself (phase 1)."
  value = [
    for h in var.source_hostnames : {
      hostname = h
      name     = local.validation_options[h].resource_record_name
      type     = local.validation_options[h].resource_record_type
      value    = local.validation_options[h].resource_record_value
    }
  ]
}

output "redirect_dns_records" {
  description = "DNS records that send each source hostname to CloudFront. Created automatically in Route 53 mode; with another DNS provider, create these yourself (phase 2). A zone apex cannot be a CNAME: use your provider's ALIAS, ANAME, or CNAME-flattening record instead."
  value = [
    for h in var.source_hostnames : {
      name  = h
      type  = "CNAME"
      value = aws_cloudfront_distribution.this.domain_name
    }
  ]
}

output "dns_managed_by_module" {
  description = "True when the module created the DNS records in Route 53; false when you must create them yourself."
  value       = local.use_route53
}
