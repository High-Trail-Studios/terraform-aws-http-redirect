# Live integration test. It CREATES REAL RESOURCES in your AWS account and
# destroys them when it finishes. Expect 15-30 minutes, mostly CloudFront
# deploying and deleting, and a cost of well under $0.01.
#
#   export TF_VAR_zone_name=example.com      # a public Route 53 zone you own
#   terraform test -test-directory=tests/integration
#
# Requires curl. The test hostname is httpredirect-test.<zone_name>, and that
# record must not already exist.

variables {
  target_url    = "https://example.com"
  redirect_code = 302
}

run "deploy" {
  variables {
    source_hostnames  = ["httpredirect-test.${var.zone_name}"]
    route53_zone_name = var.zone_name
  }

  assert {
    condition     = length(aws_route53_record.alias) == 2
    error_message = "Expected A and AAAA alias records."
  }
}

# curl --connect-to reaches the distribution directly, which avoids relying on
# local resolver caches for a record that was created moments ago.
run "https_redirect_preserves_path_and_query" {
  module {
    source = "./tests/integration/probe"
  }

  variables {
    url          = "https://httpredirect-test.${var.zone_name}/a/b.html?x=1&y"
    connect_host = run.deploy.cloudfront_domain_name
  }

  assert {
    condition     = data.external.probe.result.code == "302"
    error_message = "Expected a 302, got ${data.external.probe.result.code}."
  }
  assert {
    condition     = data.external.probe.result.location == "https://example.com/a/b.html?x=1&y"
    error_message = "Unexpected Location: ${data.external.probe.result.location}"
  }
}

run "http_redirects_in_one_hop" {
  module {
    source = "./tests/integration/probe"
  }

  variables {
    url          = "http://httpredirect-test.${var.zone_name}/"
    connect_host = run.deploy.cloudfront_domain_name
  }

  assert {
    condition     = data.external.probe.result.code == "302" && data.external.probe.result.location == "https://example.com/"
    error_message = "Plain HTTP should go straight to the target, got ${data.external.probe.result.code} ${data.external.probe.result.location}."
  }
}
