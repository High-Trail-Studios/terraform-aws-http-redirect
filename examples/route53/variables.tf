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
  default = "https://www.google.com"
}
