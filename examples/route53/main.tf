module "redirect" {
  source = "../.."

  source_hostnames  = [var.zone_name, "www.${var.zone_name}"]
  target_url        = var.target_url
  route53_zone_name = var.zone_name
}
