variable "source_hostnames" {
  description = "Hostnames to redirect FROM, e.g. [\"example.com\", \"www.example.com\"]. 1-10 lowercase hostnames with no scheme, path, port, or wildcard. All share one certificate (the first is its primary name) and one CloudFront distribution. Each must not already be an alias on another CloudFront distribution."
  type        = list(string)

  validation {
    condition     = length(var.source_hostnames) >= 1 && length(var.source_hostnames) <= 10
    error_message = "source_hostnames must contain between 1 and 10 hostnames (the default ACM per-certificate name quota)."
  }

  validation {
    condition = alltrue([
      for h in var.source_hostnames :
      length(h) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$", h))
    ])
    error_message = "Each source hostname must be a lowercase, fully qualified hostname with no scheme, path, port, trailing dot, or wildcard (e.g. \"www.example.com\")."
  }

  validation {
    condition     = length(distinct(var.source_hostnames)) == length(var.source_hostnames)
    error_message = "source_hostnames must not contain duplicates."
  }
}

variable "target_url" {
  description = "Absolute http:// or https:// URL to redirect TO, e.g. \"https://new.example.org\" or \"https://new.example.org/landing\". May include a path; may include a query string only when preserve_path is false."
  type        = string

  validation {
    condition     = can(regex("^https?://([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{0,61}[a-z0-9](/[^\\s\"'\\\\]*)?$", var.target_url))
    error_message = "target_url must be an absolute http:// or https:// URL with a lowercase hostname, no port, and no whitespace, quotes, or backslashes."
  }
}

variable "route53_zone_name" {
  description = "Public Route 53 hosted zone that contains every source hostname. When set, the module creates the certificate validation and alias records. When null, the records are returned as outputs for you to create at your DNS provider."
  type        = string
  default     = null

  validation {
    condition     = var.route53_zone_name == null || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]\\.?$", var.route53_zone_name))
    error_message = "route53_zone_name must be a lowercase domain name, e.g. \"example.com\"."
  }
}

variable "redirect_code" {
  description = "HTTP status code to send. 301/308 are permanent and are cached by browsers with no expiry, so they are hard to undo. Use 302/307 while you are still testing."
  type        = number
  default     = 301

  validation {
    condition     = contains([301, 302, 307, 308], var.redirect_code)
    error_message = "redirect_code must be one of 301, 302, 307, 308."
  }
}

variable "preserve_path" {
  description = "When true, the request path and query string are appended to target_url (old.com/a?b=1 -> new.com/a?b=1). When false, every request goes to target_url exactly."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to add to every taggable resource, merged with the module's identifying tags."
  type        = map(string)
  default     = {}
}
