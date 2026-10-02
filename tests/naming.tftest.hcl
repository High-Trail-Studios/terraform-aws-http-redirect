# Naming limits, in a separate file so they start from empty state. A run that
# changes hostnames mid-file can otherwise see the previous run's mocked
# certificate attributes.

mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [{
        domain_name           = "a-very-long-subdomain-name-for-testing-limits.another-long-label.example.com"
        resource_record_name  = "_a1.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_b1.acm-validations.aws."
      }]
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::000000000000:function/test"
    }
  }
}

variables {
  target_url = "https://new.example.org"
}

run "long_hostnames_produce_valid_names" {
  command = plan

  variables {
    source_hostnames = ["a-very-long-subdomain-name-for-testing-limits.another-long-label.example.com"]
  }

  assert {
    condition     = length(aws_cloudfront_function.this.name) <= 64 && can(regex("^[a-zA-Z0-9_-]+$", aws_cloudfront_function.this.name))
    error_message = "Function name must satisfy CloudFront's [a-zA-Z0-9-_]{1,64} rule."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this.comment) <= 128
    error_message = "Distribution comment must be at most 128 characters."
  }
}
