# Phase 1: create these at your DNS provider so ACM can issue the certificate.
output "certificate_validation_records" {
  value = module.redirect.certificate_validation_records
}

# Phase 2: create these to send traffic to the redirect.
output "redirect_dns_records" {
  value = module.redirect.redirect_dns_records
}
