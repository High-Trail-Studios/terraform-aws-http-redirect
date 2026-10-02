# terraform-aws-http-redirect

Redirect one or more hostnames to a URL, over HTTP and HTTPS, using
CloudFront, a CloudFront Function, and a free ACM certificate. There's
nothing to run or patch, and no standing cost.

```
http(s)://example.com/any/path?q=1  ──301──▶  https://new.example.org/any/path?q=1
http(s)://www.example.com/...       ──301──▶  https://new.example.org/...
```

- **Route 53 or any DNS provider.** If the domain is in Route 53, one
  `apply` does everything. If not, the module outputs the records you need to
  create at your provider.
- **Few inputs.** Two are required: `source_hostnames` and `target_url`.
- **Works from any provider region.** The certificate is pinned to us-east-1
  inside the module, so you don't need a provider alias.

## Quick start: Route 53

```hcl
module "redirect" {
  source = "github.com/High-Trail-Studios/terraform-aws-http-redirect"

  source_hostnames  = ["example.com", "www.example.com"]
  target_url        = "https://new.example.org"
  route53_zone_name = "example.com"
}
```

```sh
terraform init
terraform plan    # review: one certificate, one function, one distribution, records
terraform apply   # 5–15 minutes, mostly CloudFront deploying
```

Then confirm it works:

```sh
curl -sI https://example.com/some/path | grep -i -e '^HTTP' -e '^location'
# HTTP/2 301
# location: https://new.example.org/some/path
```

That's it. The module validates the certificate, creates `A` and `AAAA`
alias records for each hostname, and waits until CloudFront has deployed.

> **The hostname already has a record?** The module never overwrites an
> existing DNS record, so `apply` will stop with an error. See
> [Cutting over a live hostname](#cutting-over-a-live-hostname).

## Using another DNS provider (phased rollout)

Without Route 53, Terraform can't create the validation records that ACM
needs, and CloudFront won't accept a certificate until ACM has issued it. So
the rollout happens in two phases.

**Phase 1: request the certificate and get the validation records.**

```hcl
module "redirect" {
  source = "github.com/High-Trail-Studios/terraform-aws-http-redirect"

  source_hostnames = ["old.example.com"]
  target_url       = "https://new.example.org"
}

output "certificate_validation_records" {
  value = module.redirect.certificate_validation_records
}
output "redirect_dns_records" {
  value = module.redirect.redirect_dns_records
}
```

```sh
terraform init
terraform apply -target=module.redirect.aws_acm_certificate.this
terraform output certificate_validation_records
```

At your DNS provider, create each `CNAME` that this command lists. Some
providers add your domain to the end of the name automatically. If yours
does, enter only the part before your domain.

**Phase 2: create the redirect.**

```sh
terraform apply
```

This waits until ACM sees your validation records and issues the certificate,
which usually takes a few minutes and can take up to 75 minutes before it
times out. Then it deploys CloudFront.

**Phase 3: point the hostnames at CloudFront.**

```sh
terraform output redirect_dns_records
```

For each hostname, create a `CNAME` to the `dxxxx.cloudfront.net` value.
A **zone apex** (`example.com` itself) can't be a CNAME. Use your provider's
`ALIAS`, `ANAME`, or CNAME-flattening record type instead. If your provider
has none of those, you can't point the apex at CloudFront from that provider.

> **Keep the validation records.** ACM renews the certificate automatically
> before it expires, but only if the validation CNAMEs still exist. If you
> delete them, renewal fails and the redirect starts serving an expired
> certificate when the current one runs out.

## Redirect behavior

The `Location` header produced for each combination of `target_url` and
`preserve_path`:

| `target_url` | `preserve_path` | Request | `Location` |
|---|---|---|---|
| `https://new.org` | `true` | `/a/b?x=1` | `https://new.org/a/b?x=1` |
| `https://new.org/blog/` | `true` | `/post` | `https://new.org/blog/post` |
| `https://new.org/landing?src=old` | `false` | `/anything?x=1` | `https://new.org/landing?src=old` |

`target_url` can't contain `?` or `#` while `preserve_path = true`, because
there's no correct way to merge two query strings. Plan fails with an
explanation if you try.

See [Choosing a status code](#choosing-a-status-code) before picking
`redirect_code`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_source_hostnames"></a> [source\_hostnames](#input\_source\_hostnames) | Hostnames to redirect FROM, e.g. ["example.com", "www.example.com"]. 1-10 lowercase hostnames with no scheme, path, port, or wildcard. All share one certificate (the first is its primary name) and one CloudFront distribution. Each must not already be an alias on another CloudFront distribution. | `list(string)` | n/a | yes |
| <a name="input_target_url"></a> [target\_url](#input\_target\_url) | Absolute http:// or https:// URL to redirect TO, e.g. "https://new.example.org" or "https://new.example.org/landing". May include a path; may include a query string only when preserve\_path is false. | `string` | n/a | yes |
| <a name="input_preserve_path"></a> [preserve\_path](#input\_preserve\_path) | When true, the request path and query string are appended to target\_url (old.com/a?b=1 -> new.com/a?b=1). When false, every request goes to target\_url exactly. | `bool` | `true` | no |
| <a name="input_redirect_code"></a> [redirect\_code](#input\_redirect\_code) | HTTP status code to send. 301/308 are permanent and are cached by browsers with no expiry, so they are hard to undo. Use 302/307 while you are still testing. | `number` | `301` | no |
| <a name="input_route53_zone_name"></a> [route53\_zone\_name](#input\_route53\_zone\_name) | Public Route 53 hosted zone that contains every source hostname. When set, the module creates the certificate validation and alias records. When null, the records are returned as outputs for you to create at your DNS provider. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to add to every taggable resource, merged with the module's identifying tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ARN of the us-east-1 ACM certificate covering the source hostnames. |
| <a name="output_certificate_validation_records"></a> [certificate\_validation\_records](#output\_certificate\_validation\_records) | DNS records that prove ownership to ACM. Created automatically in Route 53 mode; with another DNS provider, create these yourself (phase 1). |
| <a name="output_cloudfront_distribution_id"></a> [cloudfront\_distribution\_id](#output\_cloudfront\_distribution\_id) | ID of the CloudFront distribution that serves the redirect. |
| <a name="output_cloudfront_domain_name"></a> [cloudfront\_domain\_name](#output\_cloudfront\_domain\_name) | CloudFront domain name (dxxxx.cloudfront.net) that the source hostnames must point at. |
| <a name="output_cloudfront_hosted_zone_id"></a> [cloudfront\_hosted\_zone\_id](#output\_cloudfront\_hosted\_zone\_id) | Route 53 hosted zone ID for CloudFront alias records (the same for every distribution). |
| <a name="output_dns_managed_by_module"></a> [dns\_managed\_by\_module](#output\_dns\_managed\_by\_module) | True when the module created the DNS records in Route 53; false when you must create them yourself. |
| <a name="output_redirect_dns_records"></a> [redirect\_dns\_records](#output\_redirect\_dns\_records) | DNS records that send each source hostname to CloudFront. Created automatically in Route 53 mode; with another DNS provider, create these yourself (phase 2). A zone apex cannot be a CNAME: use your provider's ALIAS, ANAME, or CNAME-flattening record instead. |
<!-- END_TF_DOCS -->

## How it works

```
viewer ──▶ CloudFront edge ──▶ CloudFront Function (viewer-request)
                                   └─▶ returns 30x + Location; origin never contacted
```

- **`aws_acm_certificate`** is created in us-east-1 with DNS validation and
  one name per source hostname.
- **`aws_cloudfront_function`** (`cloudfront-js-2.0`) builds the `Location`
  header and answers every request at the edge.
- **`aws_cloudfront_distribution`** has the hostnames as aliases,
  `PriceClass_100`, TLS 1.2+ with SNI, HTTP/2 and HTTP/3, and IPv6. CloudFront
  requires an origin, so the target host is listed as one, but no request is
  ever sent to it.
- **`aws_route53_record`** (Route 53 mode only) creates the validation records
  and the `A`/`AAAA` aliases.

Plain HTTP goes straight to the target in one hop, not
`http://old → https://old → target`.

Resources are tagged `httpredirect:source`, `httpredirect:target` and
`ManagedBy = terraform-aws-http-redirect`, so you can find them later:

```sh
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=ManagedBy,Values=terraform-aws-http-redirect
```

AWS only allows letters, digits, spaces and `+ - = . _ : / @` in tag values,
and up to 256 characters. The module replaces any other character in the
target URL (such as `?`, `&` or `#`) with `_` in the tag. The real value is in
the function code.

## Cost

There's no hourly or monthly charge. You pay per request, and a redirect
response is a few hundred bytes.

| Item | Price | Notes |
|---|---|---|
| ACM public certificate | Free | |
| CloudFront requests | ~$0.0075–$0.01 per 10,000 (NA/EU) | Always-free tier: 10M requests/month |
| CloudFront Function | $0.10 per 1M invocations | Always-free tier: 2M/month |
| Route 53 alias queries to CloudFront | Free | |
| Route 53 hosted zone | $0.50/month | Only if you create one; this module never does |

Prices are from published AWS pricing at the time of writing. Check the
current pricing pages before relying on them.

Choices made to keep costs down:

- **`PriceClass_100`** (North America and Europe edges). Viewers elsewhere are
  still redirected, from a more distant edge, which adds a few tens of
  milliseconds to one response.
- **No access logs.** Logs go to S3, which bills for storage and requests.
- **No WAF.** WAF costs $5/month per web ACL plus rule and request charges.
- **No ALB.** An ALB listener rule can also redirect, but an ALB costs about
  $16/month or more even when idle.
- **CloudFront Function, not Lambda@Edge.** It's about one-sixth the price,
  needs no IAM role, and tears down instantly. Lambda@Edge replicas can block
  `destroy` for hours.

## Security

- **Permissions.** [`docs/iam-policy.json`](docs/iam-policy.json) lists the
  actions the module calls. Drop the `Route53…` statement if you don't use
  `route53_zone_name`. You can narrow it further: scope the Route 53 actions
  to `arn:aws:route53:::hostedzone/<ZONE_ID>` and `arn:aws:route53:::change/*`.
  Note that ACM and CloudFront create actions can't be limited to resource
  ARNs that don't exist yet. This list is based on the AWS provider's API
  calls. It hasn't been tested against a policy containing only these
  actions.
- **Secrets.** The module handles none. There are no credentials, keys or
  tokens in the code, inputs or state. The certificate's private key never
  leaves ACM.
- **TLS.** The minimum version is `TLSv1.2_2021`, using SNI.
- **Overwrites.** Alias records use `allow_overwrite = false`, so the module
  never takes over an existing record without telling you. Validation records
  use `allow_overwrite = true`, because they're deterministic per hostname
  and account and carry no traffic.
- **Function input.** `target_url` is embedded in the function with
  `jsonencode()`, and input validation also rejects quotes, backslashes and
  whitespace.

## Cutting over a live hostname

If a source hostname already serves traffic, keep the old record in place
until the new distribution is ready.

**Route 53, existing `A` record.** Import the record so that `apply` changes
it to an alias in one atomic UPSERT. Terraform only does this after the
distribution is deployed.

```sh
terraform import 'module.redirect.aws_route53_record.alias["example.com/A"]' Z123EXAMPLE_example.com_A
terraform apply
```

Do the same for `AAAA` if the record exists.

**Route 53, existing `CNAME`** (often `www`). A CNAME can't coexist with an
alias record at the same name, so the swap happens in steps:

```sh
terraform apply -target=module.redirect.aws_cloudfront_distribution.this
# Distribution is up. Now delete the old CNAME in Route 53, then:
terraform apply
```

There's a gap of a minute or two between deleting the CNAME and creating the
alias. To keep the gap short, lower the CNAME's TTL a day in advance.

**Another DNS provider.** Phase 3 already works this way: you change the
record only after the redirect is live.

## Choosing a status code

| Code | Meaning | Method kept? | Cached by browsers |
|---|---|---|---|
| `301` | Moved permanently (default) | Usually becomes GET | Yes, with no expiry |
| `308` | Moved permanently | Yes | Yes, with no expiry |
| `302` | Found (temporary) | Usually becomes GET | No |
| `307` | Temporary redirect | Yes | No |

**A 301 is hard to undo.** Browsers cache it until the user clears their
cache, so changing `target_url` later won't reach visitors who already have
it cached. Test with `302`, then switch to `301` when you're sure.

## Limitations

- **GET and HEAD only.** Any other method gets a `403` from CloudFront. Form
  posts to the old hostname aren't redirected.
- **One target per module instance.** There are no path-based rules
  (`/blog/* → X`, `/shop/* → Y`). For several hostnames with different
  targets, use one module instance each, for example with `for_each`.
- **No wildcard hostnames** (`*.example.com`).
- **At most 10 hostnames per instance**, which is ACM's default quota per
  certificate.
- **A hostname can belong to only one CloudFront distribution across all of
  AWS.** If any account already uses it as an alias, `apply` fails with
  `CNAMEAlreadyExists`.
- **CAA records.** If the domain has CAA records, at least one must allow
  `amazon.com`, or ACM can't issue the certificate.
- **No HSTS or other response headers.** That's out of scope for a redirect.
- **Public zones only.** `route53_zone_name` is looked up with
  `private_zone = false`.
- **First-apply validation timeout.** In external-DNS mode, if you skip phase 1
  and run a plain `apply`, it waits up to 75 minutes for validation records you
  can't see yet. Press Ctrl-C and follow the phases.

## When not to use this

- **You already have CloudFront, an ALB, or a web server on that hostname.**
  Add a redirect rule there instead. A second distribution for the same name
  isn't possible anyway (see `CNAMEAlreadyExists`).
- **You need many path-specific rules.** Use a CloudFront Function with a
  [KeyValueStore](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html),
  or a redirect feature built into your DNS or CDN provider. Many providers
  (Cloudflare, for example) offer redirects at no extra cost.
- **Route 53 alone can't do this.** DNS can't send an HTTP redirect. That's
  why this module exists.

## Teardown

```sh
terraform destroy
```

This removes the distribution, function, certificate and any Route 53
records the module created. Deleting a CloudFront distribution takes 5–15
minutes, because it must be disabled first. Nothing is left that bills.

**Delete DNS records in the right order.** With another DNS provider,
delete the redirect records first, then run `destroy`, then delete the
validation CNAMEs. If the records outlive the distribution, the hostname
points at a CloudFront domain that no longer exists.

## Development

```sh
node --test tests/function     # CloudFront Function logic, no AWS needed
terraform test                 # module unit tests with a mock provider, no AWS needed
tofu test                      # the same, under OpenTofu
```

To run the same checks as CI's `pre-commit` job before each commit (formatting,
whitespace, private keys and other secrets), install
[pre-commit](https://pre-commit.com) 3.2 or later and OpenTofu, then run
`pre-commit install`.

The Inputs and Outputs tables are generated from `variables.tf` and
`outputs.tf` by [terraform-docs](https://terraform-docs.io), and CI fails if
they're out of date. After changing a variable or output, run
`terraform-docs .` (v0.24 or later) and commit the result.

CI runs all of these on Terraform 1.7.5 and the latest release, and on
OpenTofu 1.8.9 and the latest release. The module itself works on OpenTofu
1.8.0, but that release's test framework mishandles mocked set values, so run
the tests on 1.8.9 or later.

The **live integration test** deploys a real redirect for
`httpredirect-test.<zone>`, checks it with `curl`, and destroys it. It takes
15–30 minutes and costs well under a cent. It needs AWS credentials, `curl`
7.84 or later, and a public Route 53 zone:

```sh
export TF_VAR_zone_name=example.com
terraform init -test-directory=tests/integration
terraform test -test-directory=tests/integration
```

If the test is interrupted, check for leftover resources with the tag query
in [How it works](#how-it-works).

## Requirements

| | Version |
|---|---|
| Terraform | `>= 1.7` (or OpenTofu `>= 1.8`) |
| AWS provider | `>= 6.0, < 7.0` |

## Possible future directions

These are deliberately out of v1:

- Path-based rules via a CloudFront KeyValueStore
- Wildcard source hostnames
- Optional `price_class` input for viewers outside North America and Europe

## License

[MIT](LICENSE)
