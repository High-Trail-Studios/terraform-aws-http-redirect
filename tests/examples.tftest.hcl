# Plans each example against a mock provider, so the documented usage is
# checked on every test run.

mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        for h in ["example.com", "www.example.com", "old.example.com"] : {
          domain_name           = h
          resource_record_name  = "_a.${h}."
          resource_record_type  = "CNAME"
          resource_record_value = "_b.acm-validations.aws."
        }
      ]
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::000000000000:function/test"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0000000000TEST"
    }
  }
}

run "example_route53" {
  command = plan

  module {
    source = "./examples/route53"
  }

  assert {
    condition     = length(module.redirect.redirect_dns_records) == 2
    error_message = "Route 53 example should redirect the apex and www."
  }
}

run "example_external_dns" {
  command = plan

  module {
    source = "./examples/external-dns"
  }

  assert {
    condition     = length(output.certificate_validation_records) == 1
    error_message = "External DNS example should expose the validation record."
  }
}
