locals {
  use_route53 = var.route53_zone_name != null
  # "" rather than null when unused: Terraform < 1.12 does not short-circuit
  # `||`, so the zone precondition below still evaluates this.
  zone_name = local.use_route53 ? trimsuffix(var.route53_zone_name, ".") : ""

  primary_hostname = var.source_hostnames[0]
  target_host      = regex("^https?://([^/]+)", var.target_url)[0]

  # When the path is appended, a trailing slash on the target would turn
  # "/foo" into "//foo".
  target_base = var.preserve_path ? trimsuffix(var.target_url, "/") : var.target_url

  # CloudFront function names allow [a-zA-Z0-9-_] and at most 64 characters.
  # A hash of the hostnames keeps the name deterministic and unique per redirect.
  name_hash = substr(sha1(join(",", sort(var.source_hostnames))), 0, 8)
  name      = "httpredirect-${trim(substr(replace(local.primary_hostname, ".", "-"), 0, 40), "-")}-${local.name_hash}"

  # AWS tag values allow letters, digits, spaces and + - = . _ : / @, up to 256
  # characters. Any other character (?, &, # ...) is replaced with "_".
  tag_source = substr(join(" ", var.source_hostnames), 0, 256)
  tag_target = substr(replace(var.target_url, "/[^a-zA-Z0-9 +\\-=._:/@]/", "_"), 0, 256)

  tags = merge(var.tags, {
    "httpredirect:source" = local.tag_source
    "httpredirect:target" = local.tag_target
    "ManagedBy"           = "terraform-aws-http-redirect"
  })

  # CloudFront comments are limited to 128 characters.
  comment = substr("Redirect ${join(", ", var.source_hostnames)} -> ${var.target_url}", 0, 128)

  # One validation record per hostname. Keyed on the input hostnames (known at
  # plan time) rather than on the certificate's computed attributes.
  validation_options = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => dvo
  }
}

# -----------------------------------------------------------------------------
# Certificate (CloudFront only accepts certificates from us-east-1)
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  region = "us-east-1"

  domain_name               = local.primary_hostname
  subject_alternative_names = slice(var.source_hostnames, 1, length(var.source_hostnames))
  validation_method         = "DNS"
  tags                      = local.tags

  lifecycle {
    # Replacing the certificate (e.g. adding a hostname) must not detach the
    # live one from CloudFront before the new one is attached.
    create_before_destroy = true

    precondition {
      condition = !local.use_route53 || alltrue([
        for h in var.source_hostnames : h == local.zone_name || endswith(h, ".${local.zone_name}")
      ])
      error_message = "Every source hostname must be inside route53_zone_name (\"${local.zone_name}\")."
    }

    precondition {
      condition     = !contains(var.source_hostnames, local.target_host)
      error_message = "target_url points at one of the source hostnames, which would create a redirect loop."
    }

    precondition {
      condition     = !var.preserve_path || !can(regex("[?#]", var.target_url))
      error_message = "target_url cannot contain a query string or fragment when preserve_path is true. Set preserve_path = false to redirect to a fixed URL."
    }
  }
}

data "aws_route53_zone" "this" {
  count = local.use_route53 ? 1 : 0

  name         = local.zone_name
  private_zone = false
}

resource "aws_route53_record" "validation" {
  for_each = local.use_route53 ? toset(var.source_hostnames) : toset([])

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = local.validation_options[each.key].resource_record_name
  type    = local.validation_options[each.key].resource_record_type
  records = [local.validation_options[each.key].resource_record_value]
  ttl     = 300

  # Validation records are deterministic for a given hostname and account and
  # carry no traffic. Overwriting a leftover copy from an earlier attempt is safe.
  allow_overwrite = true
}

# In external-DNS mode this waits until you have created the validation
# records. See "Using another DNS provider" in the README.
resource "aws_acm_certificate_validation" "this" {
  region = "us-east-1"

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = local.use_route53 ? [for r in aws_route53_record.validation : r.fqdn] : null
}

# -----------------------------------------------------------------------------
# Redirect logic
# -----------------------------------------------------------------------------

resource "aws_cloudfront_function" "this" {
  name    = local.name
  runtime = "cloudfront-js-2.0"
  comment = local.comment
  publish = true

  code = templatefile("${path.module}/src/redirect.js.tftpl", {
    target_json   = jsonencode(local.target_base)
    redirect_code = var.redirect_code
    preserve_path = var.preserve_path
  })
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  comment         = local.comment
  aliases         = var.source_hostnames

  # Every request is answered by the viewer-request function, so the origin is
  # never contacted. The target host is used only because CloudFront requires
  # an origin.
  origin {
    origin_id   = "unused"
    domain_name = local.target_host

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = "unused"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    cache_policy_id  = data.aws_cloudfront_cache_policy.caching_disabled.id

    # Redirect plain HTTP straight to the target in one hop, rather than
    # bouncing through https://source first.
    viewer_protocol_policy = "allow-all"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.this.arn
    }
  }

  # Cheapest class: North America and Europe edges. Viewers elsewhere are still
  # served, just from a more distant edge.
  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# DNS (Route 53 mode only)
# -----------------------------------------------------------------------------

resource "aws_route53_record" "alias" {
  for_each = local.use_route53 ? {
    for pair in setproduct(var.source_hostnames, ["A", "AAAA"]) : "${pair[0]}/${pair[1]}" => {
      name = pair[0]
      type = pair[1]
    }
  } : {}

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value.name
  type    = each.value.type

  # Never take over an existing record silently. If the hostname already
  # points somewhere, apply fails and you decide how to cut over.
  allow_overwrite = false

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
