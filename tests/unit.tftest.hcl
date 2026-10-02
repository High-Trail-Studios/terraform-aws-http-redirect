# Unit tests. These use a mock AWS provider, so they need no credentials and
# create nothing. Run with `terraform test` (or `tofu test`).

mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_a1.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_b1.acm-validations.aws."
        },
        {
          domain_name           = "www.example.com"
          resource_record_name  = "_a2.www.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_b2.acm-validations.aws."
        },
      ]
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::000000000000:function/test"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0000000000TEST"
    }
  }
}

variables {
  source_hostnames = ["example.com", "www.example.com"]
  target_url       = "https://new.example.org"
}

# -----------------------------------------------------------------------------
# External DNS mode (the default)
# -----------------------------------------------------------------------------

run "external_dns_creates_no_route53_records" {
  assert {
    condition     = length(data.aws_route53_zone.this) == 0
    error_message = "No hosted zone lookup should happen without route53_zone_name."
  }
  assert {
    condition     = length(aws_route53_record.validation) == 0 && length(aws_route53_record.alias) == 0
    error_message = "No Route 53 records should be created without route53_zone_name."
  }
  assert {
    condition     = output.dns_managed_by_module == false
    error_message = "dns_managed_by_module should be false in external DNS mode."
  }
}

run "external_dns_outputs_every_record_needed" {
  assert {
    condition = output.certificate_validation_records == [
      { hostname = "example.com", name = "_a1.example.com.", type = "CNAME", value = "_b1.acm-validations.aws." },
      { hostname = "www.example.com", name = "_a2.www.example.com.", type = "CNAME", value = "_b2.acm-validations.aws." },
    ]
    error_message = "certificate_validation_records should list one record per hostname, in input order."
  }
  assert {
    condition = output.redirect_dns_records == [
      { name = "example.com", type = "CNAME", value = "d111111abcdef8.cloudfront.net" },
      { name = "www.example.com", type = "CNAME", value = "d111111abcdef8.cloudfront.net" },
    ]
    error_message = "redirect_dns_records should point every hostname at the distribution."
  }
}

run "external_dns_still_waits_for_validation" {
  assert {
    condition     = aws_acm_certificate_validation.this.validation_record_fqdns == null
    error_message = "External DNS mode should not pass validation FQDNs."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == aws_acm_certificate_validation.this.certificate_arn
    error_message = "The distribution must use the validated certificate, so it waits for issuance."
  }
}

# -----------------------------------------------------------------------------
# Certificate and distribution shape
# -----------------------------------------------------------------------------

run "certificate_is_in_us_east_1_and_covers_all_hostnames" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.region == "us-east-1" && aws_acm_certificate_validation.this.region == "us-east-1"
    error_message = "CloudFront requires the certificate in us-east-1."
  }
  assert {
    condition     = aws_acm_certificate.this.domain_name == "example.com"
    error_message = "The first hostname should be the certificate's primary name."
  }
  assert {
    condition     = toset(aws_acm_certificate.this.subject_alternative_names) == toset(["www.example.com"])
    error_message = "The remaining hostnames should be SANs."
  }
  assert {
    condition     = aws_acm_certificate.this.validation_method == "DNS"
    error_message = "Validation must be DNS so it can be automated."
  }
}

run "distribution_is_cheap_and_secure" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_100"
    error_message = "Use the cheapest price class."
  }
  assert {
    condition     = toset(aws_cloudfront_distribution.this.aliases) == toset(["example.com", "www.example.com"])
    error_message = "Every source hostname should be an alias."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "Minimum TLS version should be TLSv1.2_2021."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only"
    error_message = "Use SNI; dedicated-IP SSL costs $600/month."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this.logging_config) == 0
    error_message = "Access logging should be off by default (it accrues S3 cost)."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == null
    error_message = "No WAF by default (it has a standing monthly cost)."
  }
}

run "function_runs_on_viewer_request" {
  command = plan

  assert {
    condition     = aws_cloudfront_function.this.runtime == "cloudfront-js-2.0" && aws_cloudfront_function.this.publish
    error_message = "Function should use cloudfront-js-2.0 and be published."
  }
  assert {
    condition     = one([for b in aws_cloudfront_distribution.this.default_cache_behavior : one(b.function_association).event_type]) == "viewer-request"
    error_message = "Function must run on viewer-request so the origin is never contacted."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, "var TARGET = \"https://new.example.org\";")
    error_message = "Rendered code should embed the target URL."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, "var STATUS_CODE = 301;") && strcontains(aws_cloudfront_function.this.code, "var PRESERVE_PATH = true;")
    error_message = "Rendered code should default to 301 with path preservation."
  }
}

run "trailing_slash_is_stripped_when_preserving_path" {
  command = plan

  variables {
    target_url = "https://new.example.org/blog/"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, "var TARGET = \"https://new.example.org/blog\";")
    error_message = "Trailing slash should be stripped so paths don't double up."
  }
}

run "fixed_target_keeps_query_and_slash" {
  command = plan

  variables {
    target_url    = "https://new.example.org/landing/?utm_source=old&x=1"
    preserve_path = false
    redirect_code = 302
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, jsonencode("https://new.example.org/landing/?utm_source=old&x=1"))
    error_message = "With preserve_path = false the target should be used verbatim."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, "var STATUS_CODE = 302;") && strcontains(aws_cloudfront_function.this.code, "var PRESERVE_PATH = false;")
    error_message = "Rendered code should reflect redirect_code and preserve_path."
  }
}

# -----------------------------------------------------------------------------
# Naming and tags
# -----------------------------------------------------------------------------

run "tags_identify_source_and_target" {
  command = plan

  variables {
    tags = { Team = "web" }
  }

  assert {
    condition     = aws_acm_certificate.this.tags["httpredirect:source"] == "example.com www.example.com"
    error_message = "Source tag should list the hostnames."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.tags["httpredirect:target"] == "https://new.example.org"
    error_message = "Target tag should hold the target URL."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.tags["Team"] == "web" && aws_acm_certificate.this.tags["ManagedBy"] == "terraform-aws-http-redirect"
    error_message = "Caller tags should merge with module tags."
  }
}

run "tag_values_are_sanitized" {
  command = plan

  variables {
    target_url    = "https://new.example.org/p?a=1&b=2#frag"
    preserve_path = false
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["httpredirect:target"] == "https://new.example.org/p_a=1_b=2_frag"
    error_message = "Characters that AWS rejects in tag values should be replaced with '_'."
  }
}

run "names_are_deterministic_and_order_independent" {
  command = plan

  variables {
    source_hostnames = ["www.example.com", "example.com"]
  }

  assert {
    condition     = aws_cloudfront_function.this.name == "httpredirect-www-example-com-${substr(sha1("example.com,www.example.com"), 0, 8)}"
    error_message = "Function name should be readable and hash the sorted hostnames."
  }
}

# -----------------------------------------------------------------------------
# Route 53 mode
# -----------------------------------------------------------------------------

run "route53_creates_validation_and_alias_records" {
  variables {
    route53_zone_name = "example.com"
  }

  assert {
    condition     = output.dns_managed_by_module
    error_message = "dns_managed_by_module should be true in Route 53 mode."
  }
  assert {
    condition     = data.aws_route53_zone.this[0].private_zone == false && data.aws_route53_zone.this[0].name == "example.com"
    error_message = "Zone lookup must target the public zone."
  }
  assert {
    condition     = length(aws_route53_record.validation) == 2
    error_message = "One validation record per hostname."
  }
  assert {
    condition     = aws_route53_record.validation["www.example.com"].name == "_a2.www.example.com." && aws_route53_record.validation["www.example.com"].records == toset(["_b2.acm-validations.aws."])
    error_message = "Validation records should come from the certificate."
  }
  assert {
    condition     = toset(keys(aws_route53_record.alias)) == toset(["example.com/A", "example.com/AAAA", "www.example.com/A", "www.example.com/AAAA"])
    error_message = "Each hostname needs an A and an AAAA alias (IPv6 is enabled)."
  }
  assert {
    condition     = alltrue([for r in aws_route53_record.alias : r.allow_overwrite == false])
    error_message = "Alias records must never overwrite existing records silently."
  }
  assert {
    condition = alltrue([for r in aws_route53_record.alias :
      one(r.alias).name == "d111111abcdef8.cloudfront.net" && one(r.alias).zone_id == "Z2FDTNDATAQYW2"
    ])
    error_message = "Alias records should point at the distribution."
  }
  assert {
    condition     = aws_acm_certificate_validation.this.validation_record_fqdns == toset([for r in aws_route53_record.validation : r.fqdn])
    error_message = "Route 53 mode should wait on the created validation records."
  }
}

run "route53_accepts_trailing_dot_and_subdomains" {
  command = plan

  variables {
    route53_zone_name = "example.com."
  }

  assert {
    condition     = data.aws_route53_zone.this[0].name == "example.com"
    error_message = "Trailing dot on the zone name should be normalised."
  }
}

run "route53_rejects_hostname_outside_zone" {
  command = plan

  variables {
    source_hostnames  = ["example.com", "www.other.net"]
    route53_zone_name = "example.com"
  }

  expect_failures = [aws_acm_certificate.this]
}

run "route53_rejects_suffix_lookalike" {
  command = plan

  variables {
    source_hostnames  = ["notexample.com"]
    route53_zone_name = "example.com"
  }

  expect_failures = [aws_acm_certificate.this]
}

# -----------------------------------------------------------------------------
# Preconditions
# -----------------------------------------------------------------------------

run "rejects_redirect_loop" {
  command = plan

  variables {
    target_url = "https://www.example.com/new"
  }

  expect_failures = [aws_acm_certificate.this]
}

run "rejects_query_in_target_when_preserving_path" {
  command = plan

  variables {
    target_url = "https://new.example.org/?a=1"
  }

  expect_failures = [aws_acm_certificate.this]
}

run "rejects_fragment_in_target_when_preserving_path" {
  command = plan

  variables {
    target_url = "https://new.example.org/#top"
  }

  expect_failures = [aws_acm_certificate.this]
}

# -----------------------------------------------------------------------------
# Input validation
# -----------------------------------------------------------------------------

run "rejects_empty_hostnames" {
  command = plan
  variables {
    source_hostnames = []
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_too_many_hostnames" {
  command = plan
  variables {
    source_hostnames = [for i in range(11) : "h${i}.example.com"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_duplicate_hostnames" {
  command = plan
  variables {
    source_hostnames = ["example.com", "example.com"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_uppercase_hostname" {
  command = plan
  variables {
    source_hostnames = ["Example.com"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_hostname_with_scheme" {
  command = plan
  variables {
    source_hostnames = ["https://example.com"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_wildcard_hostname" {
  command = plan
  variables {
    source_hostnames = ["*.example.com"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_single_label_hostname" {
  command = plan
  variables {
    source_hostnames = ["localhost"]
  }
  expect_failures = [var.source_hostnames]
}

run "rejects_target_without_scheme" {
  command = plan
  variables {
    target_url = "new.example.org"
  }
  expect_failures = [var.target_url]
}

run "rejects_non_http_target" {
  command = plan
  variables {
    target_url = "ftp://new.example.org"
  }
  expect_failures = [var.target_url]
}

run "rejects_target_with_port" {
  command = plan
  variables {
    target_url = "https://new.example.org:8443/"
  }
  expect_failures = [var.target_url]
}

run "rejects_target_with_quote" {
  command = plan
  variables {
    target_url    = "https://new.example.org/\"x"
    preserve_path = false
  }
  expect_failures = [var.target_url]
}

run "rejects_unsupported_redirect_code" {
  command = plan
  variables {
    redirect_code = 303
  }
  expect_failures = [var.redirect_code]
}

run "accepts_http_target_and_all_redirect_codes" {
  command = plan
  variables {
    target_url    = "http://legacy.example.org/path-ok_1.html"
    redirect_code = 308
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.this.code, "var STATUS_CODE = 308;")
    error_message = "308 should be accepted."
  }
}
