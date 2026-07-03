<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The full surface of the module, everything scoped to a disposable resource group so the Deny effects
govern nothing but the example itself. The baseline exercises required parameters (allowed locations,
VM SKUs), curated Deny defaults, an effect override, the fixed-Deny require-tag policy escalated to
enforced, the identity-bearing Modify policy (system-assigned identity plus its automatic Contributor
grant), and the MCSB initiative with a custom non-compliance message. The engine exercises a custom
definition (HCL policy rule), a custom initiative mixing that definition with a built-in, an
assignment with per-reference non-compliance messages, a built-in assignment with overrides and
resource selectors, and exemptions targeting a baseline entry (Mitigated) and an engine assignment
(time-boxed Waiver). The NSP guardrails are pinned to a real network security perimeter created by the
example, auditing associations not in Enforced mode and storage/key vault resources outside the
approved perimeter. Management-group scope is exercised in [`tests`](../../tests) with a mocked
provider, since the CI principal holds subscription Owner only. Run it with `just e2e complete`,
which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  nsp_name = "nsp-${var.short}-${var.loc}-${terraform.workspace}-002"

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

# A real network security perimeter for the NSP guardrails to pin (its id feeds
# approved_perimeter_ids below).
module "nsp" {
  source  = "libre-devops/network-security-perimeter/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  network_security_perimeters = {
    (local.nsp_name) = {}
  }
}

# Complete call: the full surface. Everything is scoped to this example's resource group so the Deny
# effects only govern an empty, disposable RG; the same shapes work unchanged at management group or
# subscription scope. The scope id is computed (the RG is created in this plan), hence scope_type.
module "policy" {
  source = "../../"

  scope_id   = module.rg.ids[local.rg_name]
  scope_type = "resource_group"
  location   = local.location # for the identity-bearing Modify assignment

  # ---------- NSP guardrails: ready-made custom policies (no built-ins exist for this) ----------
  # Flags associations not in Enforced mode, and storage accounts / key vaults in the scope that are
  # not associated with the approved perimeter above.
  nsp_guardrails = {
    approved_perimeter_ids = [module.nsp.ids[local.nsp_name]]
    definition_name_suffix = "-${terraform.workspace}"
  }

  # ---------- Resource group lock guardrails: DeployIfNotExists keeps locks on tagged groups ----------
  # ReadOnly where BusinessLevel = Critical, CanNotDelete where BusinessLevel = Production. The
  # assignments carry system-assigned identities granted User Access Administrator at the scope
  # THROUGH the engine, so those grants exist only while the guardrail does. No resource group in
  # this stack carries the tags, deliberately: a remediated ReadOnly lock would block the destroy.
  rg_lock_guardrails = {
    definition_name_suffix = "-${terraform.workspace}"
  }

  # ---------- Governance guardrails: cherry-picked from real estates, audit-first ----------
  # Role assignments granting unapproved roles to service principals, and NSG rules allowing
  # inbound traffic from anywhere or to every port.
  rbac_guardrails = {
    approved_role_definition_ids = [
      "b24988ac-6180-42a0-ab88-20f7382dd24c", # Contributor
      "acdd72a7-3385-48ef-bd42-f606fba81ae7", # Reader
      "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor
    ]
    definition_name_suffix = "-${terraform.workspace}"
  }

  nsg_guardrails = {
    definition_name_suffix = "-${terraform.workspace}"
  }

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
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_nsp"></a> [nsp](#module\_nsp) | libre-devops/network-security-perimeter/azurerm | ~> 4.0 |
| <a name="module_policy"></a> [policy](#module\_policy) | ../../ | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_baseline_assignment_ids"></a> [baseline\_assignment\_ids](#output\_baseline\_assignment\_ids) | Map of baseline catalog key to assignment id. |
| <a name="output_baseline_catalog_keys"></a> [baseline\_catalog\_keys](#output\_baseline\_catalog\_keys) | Every key the curated baseline catalog offers. |
| <a name="output_identity_role_assignment_ids"></a> [identity\_role\_assignment\_ids](#output\_identity\_role\_assignment\_ids) | Role assignments granted to policy-assignment managed identities. |
| <a name="output_policy_assignments"></a> [policy\_assignments](#output\_policy\_assignments) | All assignments with id, scope, enforcement, and identity principal. |
| <a name="output_policy_definition_ids"></a> [policy\_definition\_ids](#output\_policy\_definition\_ids) | Map of custom definition key to definition id. |
| <a name="output_policy_exemptions"></a> [policy\_exemptions](#output\_policy\_exemptions) | All exemptions with id, category, and the exempted assignment. |
| <a name="output_policy_set_definition_ids"></a> [policy\_set\_definition\_ids](#output\_policy\_set\_definition\_ids) | Map of custom initiative key to set definition id. |
<!-- END_TF_DOCS -->
