variable "region" {
  type    = string
  default = "us-east-1"
}

variable "source_hostnames" {
  type    = list(string)
  default = ["old.example.com"]
}

variable "target_url" {
  type    = string
  default = "https://new.example.org"
}
