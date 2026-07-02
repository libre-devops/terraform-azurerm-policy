locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"

  # Custom definitions and initiatives are subscription-global, so their names carry the workspace to
  # keep concurrent runs from colliding (the example resource group is already per-stack).
  def_suffix = terraform.workspace
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-policy" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# Complete call: the full surface. Everything is scoped to this example's resource group so the Deny
# effects only govern an empty, disposable RG; the same shapes work unchanged at management group or
# subscription scope. The scope id is computed (the RG is created in this plan), hence scope_type.
module "policy" {
  source = "../../"

  scope_id   = module.rg.ids[local.rg_name]
  scope_type = "resource_group"
  location   = local.location # for the identity-bearing Modify assignment

  # ---------- Curated baseline: defaults, parameters, overrides, and an identity policy ----------
  baseline_policies = {
    # Required-parameter entries.
    allowed_locations = {
      parameters = { listOfAllowedLocations = ["uksouth", "ukwest"] }
    }
    allowed_vm_skus = {
      parameters = { listOfAllowedSKUs = ["Standard_B2s", "Standard_B2ms", "Standard_D2s_v5"] }
    }

    # Curated defaults (hard guardrails arrive as Deny).
    storage_deny_public_access = {}
    storage_secure_transfer    = {}
    storage_minimum_tls        = {}
    keyvault_soft_delete       = {}
    keyvault_firewall_enabled  = {}
    nic_no_public_ips          = {}
    appservice_https_only      = {}

    # Effect override: keep the network-restriction policy quieter than its curated Audit.
    storage_restrict_network_access = { effect = "Audit" }

    # Fixed-Deny tag policy: defaults to DoNotEnforce (audit-style rollout); escalated here.
    require_tag_on_resources = {
      parameters = { tagName = "CostCentre" }
      enforce    = true
    }

    # Modify policy: the assignment gets a system-assigned identity and the module grants it the
    # Contributor role the definition requires, at the assignment scope.
    inherit_tag_from_rg = {
      parameters = { tagName = "CostCentre" }
    }

    # The MCSB initiative (audit-natured), with a custom non-compliance message.
    mcsb = {
      non_compliance_message = "Flagged by the Microsoft cloud security benchmark. Review the compliance detail in the portal."
    }

    # Noisy audits, surfaced for compliance data.
    vm_management_ports_closed = {}
    audit_custom_rbac_roles    = {}
  }

  # ---------- Engine: custom definitions ----------
  policy_definitions = {
    # The drop-a-file workflow: the rule lives in a versioned .json file (write it by hand or export
    # from the portal), and adding a policy is one file plus one entry here.
    deny-public-ip = {
      name         = "deny-public-ip-${local.def_suffix}"
      display_name = "Deny public IP addresses"
      description  = "Blocks creation of standalone public IP addresses in the scope."
      mode         = "Indexed"
      policy_rule  = file("${path.module}/policies/deny-public-ip.json")
    }

    # The inline-HCL workflow: the rule is Terraform-native and parameterised.
    approved-providers = {
      name         = "approved-providers-${local.def_suffix}"
      display_name = "Approved resource providers"
      description  = "Only resource providers on the approved list may be deployed in the scope."
      mode         = "Indexed"
      policy_rule = {
        if = {
          not = {
            value = "[first(split(field('type'), '/'))]"
            in    = "[parameters('approvedProviders')]"
          }
        }
        then = { effect = "[parameters('effect')]" }
      }
      parameters = {
        approvedProviders = {
          type     = "Array"
          metadata = { displayName = "Approved resource providers", description = "Resource providers which may be deployed." }
        }
        effect = {
          type          = "String"
          allowedValues = ["Audit", "Deny", "Disabled"]
          defaultValue  = "Audit"
          metadata      = { displayName = "Effect", description = "The effect of the policy." }
        }
      }
      metadata = { category = "General", version = "1.0.0" }
    }
  }

  # ---------- Engine: a custom initiative mixing the custom definition and a built-in ----------
  policy_set_definitions = {
    governance-baseline = {
      name         = "governance-baseline-${local.def_suffix}"
      display_name = "Governance baseline"
      description  = "Provider allow-listing plus custom-role auditing, grouped as one initiative."
      policy_definition_references = [
        {
          definition_key = "approved-providers"
          reference_id   = "approvedProviders"
          parameter_values = {
            approvedProviders = { value = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Network", "Microsoft.Resources"] }
            effect            = { value = "Audit" }
          }
        },
        {
          # Audit usage of custom RBAC roles (built-in, verified GUID).
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/a451c1ef-c6ca-483d-87ed-f49761e3ffb5"
          reference_id         = "auditCustomRoles"
        },
      ]
    }
  }

  # ---------- Engine: assignments of the initiative and a built-in, with the full block surface ----
  policy_assignments = {
    # The file-based custom definition, assigned by key.
    deny-public-ip = {
      definition_key = "deny-public-ip"
      display_name   = "Deny public IP addresses"
    }

    governance = {
      set_definition_key = "governance-baseline"
      display_name       = "Governance baseline"
      description        = "Assigns the custom governance initiative."
      non_compliance_messages = [
        { content = "Blocked or flagged by the governance baseline." },
        { content = "Only approved resource providers may be used.", policy_definition_reference_id = "approvedProviders" },
      ]
    }

    # A built-in assigned by literal id, exercising overrides and resource selectors: the effect is
    # overridden to Disabled, and evaluation is narrowed to UK locations.
    secure-transfer-tuned = {
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"
      display_name         = "Secure transfer (tuned with overrides and selectors)"
      enforce              = false
      overrides = [
        { value = "Disabled" }
      ]
      resource_selectors = [
        {
          name      = "uk-only"
          selectors = [{ kind = "resourceLocation", in = ["uksouth", "ukwest"] }]
        }
      ]
    }
  }

  # ---------- Engine: exemptions targeting a baseline entry and an engine assignment ----------
  policy_exemptions = {
    mcsb-mitigated = {
      baseline_key       = "mcsb"
      exemption_category = "Mitigated"
      display_name       = "MCSB mitigated for the example scope"
      description        = "Compensating controls documented in the risk register."
    }

    governance-waiver = {
      assignment_key     = "governance"
      exemption_category = "Waiver"
      expires_on         = "2027-01-01T00:00:00Z"
      display_name       = "Governance waived during the example's lifetime"
      description        = "Time-boxed waiver with an explicit review date."
    }
  }
}
