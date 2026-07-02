locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# Minimal call: three no-parameter guardrails from the curated baseline, assigned at resource group
# scope so their Deny effects only govern this example's resource group. The scope id comes from a
# resource created in this same plan (so it is unknown at plan time), which is exactly what the
# explicit scope_type is for.
module "policy" {
  source = "../../"

  scope_id   = module.rg.ids[local.rg_name]
  scope_type = "resource_group"

  baseline_policies = {
    # Empty entries accept the curated defaults (these two arrive as Deny).
    storage_deny_public_access = {}
    storage_secure_transfer    = {}

    # Overriding a curated default is one attribute: soften soft-delete from Deny to Audit.
    keyvault_soft_delete = { effect = "Audit" }
  }
}
