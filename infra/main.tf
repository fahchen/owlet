# The website's hosting: a Cloudflare Pages project on owlet.fahchen.dev, and the token the deploy
# workflow (.github/workflows/site.yml) uses, written straight into the repository's Actions secrets.
#
# Credentials come from the environment, never from files in this directory:
#   CLOUDFLARE_API_TOKEN  a token allowed to edit Pages, DNS of fahchen.dev, and account API tokens
#   GITHUB_TOKEN          e.g. `gh auth token`; allowed to write the repository's Actions secrets
provider "cloudflare" {}

provider "github" {
  owner = var.github_owner
}

variable "account_id" {
  description = "Cloudflare account that owns the fahchen.dev zone."
  type        = string
}

variable "github_owner" {
  type    = string
  default = "fahchen"
}

variable "github_repository" {
  type    = string
  default = "owlet"
}

locals {
  domain = "owlet.fahchen.dev"
}

data "cloudflare_zone" "fahchen" {
  filter = { name = "fahchen.dev" }
}

resource "cloudflare_pages_project" "owlet" {
  account_id        = var.account_id
  name              = "owlet"
  production_branch = "main"
}

resource "cloudflare_pages_domain" "owlet" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.owlet.name
  name         = local.domain
}

resource "cloudflare_dns_record" "owlet" {
  zone_id = data.cloudflare_zone.fahchen.zone_id
  name    = local.domain
  type    = "CNAME"
  content = cloudflare_pages_project.owlet.subdomain
  proxied = true
  ttl     = 1
}

# The deploy token can do one thing: upload to Pages in this account.
data "cloudflare_account_api_token_permission_groups_list" "pages_write" {
  account_id = var.account_id
  name       = "Pages Write"
}

resource "cloudflare_account_token" "deploy" {
  account_id = var.account_id
  name       = "owlet site deploy (GitHub Actions)"
  policies = [{
    effect            = "allow"
    permission_groups = [{ id = data.cloudflare_account_api_token_permission_groups_list.pages_write.result[0].id }]
    resources         = jsonencode({ "com.cloudflare.api.account.${var.account_id}" = "*" })
  }]
}

resource "github_actions_secret" "api_token" {
  repository  = var.github_repository
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = cloudflare_account_token.deploy.value
}

resource "github_actions_secret" "account_id" {
  repository  = var.github_repository
  secret_name = "CLOUDFLARE_ACCOUNT_ID"
  value       = var.account_id
}

output "url" {
  value = "https://${local.domain}"
}
