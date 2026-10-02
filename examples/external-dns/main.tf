module "redirect" {
  source = "../.."

  source_hostnames = var.source_hostnames
  target_url       = var.target_url
}
