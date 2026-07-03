# Governance guardrails cherry-picked from real estates: custom policies that catch the quiet
# mistakes built-ins do not. Both are opt-in and audit-first, following the same pattern as the
# NSP and resource group lock guardrails.

variable "rbac_guardrails" {
  description = <<DESC
Opt-in RBAC governance; null (the default) creates nothing. Set to an object with
approved_role_definition_ids (role definition GUIDs, for example the output of
az role definition list) to enable "rbac-approved-principal-roles": role assignments granting a
role OUTSIDE the approved list to the covered principal types are audited (or denied). This is
the policy answer to roles quietly accumulating on service principals and managed identities.

Optional attributes: principal_types (default ["ServicePrincipal"]; add "User" and "Group" to
cover humans too), effect (Audit | Deny | Disabled, default Audit; move to Deny once the audit is
quiet), definition_name_suffix. Remember the policy sees role definition IDS, so approved custom
roles must be listed by their full GUID as well.
DESC

  type    = any
  default = null
}

variable "nsg_guardrails" {
  description = <<DESC
Opt-in NSG hygiene; null (the default) creates nothing. Set to an object (empty {} is valid) to
enable "nsg-permissive-inbound-rule": NSG security rules that Allow Inbound traffic with a
wildcard destination port or a wildcard/Internet source are audited (or denied). The companion
Conftest rego warns about the same shapes at plan time; this is the platform-side enforcement for
everything that does not come through your pipelines.

Optional attributes: effect (Audit | Deny | Disabled, default Audit), definition_name_suffix.
DESC

  type    = any
  default = null
}

locals {
  rbac_guardrails_enabled = var.rbac_guardrails != null
  nsg_guardrails_enabled  = var.nsg_guardrails != null

  # contains(keys()) guards, not try(): see the NSP guardrails note on unknown-poisoning.
  rbac_attr_keys = local.rbac_guardrails_enabled ? keys(var.rbac_guardrails) : []
  nsg_attr_keys  = local.nsg_guardrails_enabled ? keys(var.nsg_guardrails) : []

  rbac_approved_ids_raw = contains(local.rbac_attr_keys, "approved_role_definition_ids") ? var.rbac_guardrails.approved_role_definition_ids : null
  rbac_approved_ids     = local.rbac_approved_ids_raw == null ? [] : local.rbac_approved_ids_raw

  rbac_principal_types_raw = contains(local.rbac_attr_keys, "principal_types") ? var.rbac_guardrails.principal_types : null
  rbac_principal_types     = local.rbac_principal_types_raw == null ? ["ServicePrincipal"] : local.rbac_principal_types_raw

  rbac_effect_raw = contains(local.rbac_attr_keys, "effect") ? var.rbac_guardrails.effect : null
  rbac_effect     = local.rbac_effect_raw == null ? "Audit" : local.rbac_effect_raw

  rbac_suffix_raw = contains(local.rbac_attr_keys, "definition_name_suffix") ? var.rbac_guardrails.definition_name_suffix : null
  rbac_suffix     = local.rbac_suffix_raw == null ? "" : local.rbac_suffix_raw

  nsg_effect_raw = contains(local.nsg_attr_keys, "effect") ? var.nsg_guardrails.effect : null
  nsg_effect     = local.nsg_effect_raw == null ? "Audit" : local.nsg_effect_raw

  nsg_suffix_raw = contains(local.nsg_attr_keys, "definition_name_suffix") ? var.nsg_guardrails.definition_name_suffix : null
  nsg_suffix     = local.nsg_suffix_raw == null ? "" : local.nsg_suffix_raw

  # The role ids arrive as GUIDs; the policy compares full definition ids.
  rbac_approved_definition_ids = [
    for id in local.rbac_approved_ids :
    can(regex("^/providers/", id)) ? id : "/providers/Microsoft.Authorization/roleDefinitions/${id}"
  ]

  governance_effect_parameter = {
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
      metadata      = { displayName = "Effect", description = "The effect of the policy." }
    }
  }

  rbac_definitions_cfg = local.rbac_guardrails_enabled && length(local.rbac_approved_ids) > 0 ? {
    "rbac-approved-principal-roles" = {
      name         = "rbac-approved-principal-roles${local.rbac_suffix}"
      display_name = "Role assignments for covered principal types should use approved roles"
      description  = "Audits (or denies) role assignments granting a role outside the approved list to the covered principal types; the policy answer to roles quietly accumulating on service principals."
      mode         = "All"
      policy_rule  = file("${path.module}/policies/rbac-approved-principal-roles.json")
      parameters = merge(local.governance_effect_parameter, {
        principalTypes = {
          type          = "Array"
          allowedValues = ["ServicePrincipal", "User", "Group"]
          metadata      = { displayName = "Covered principal types", description = "Principal types the approved-role list applies to." }
        }
        approvedRoleDefinitionIds = {
          type     = "Array"
          metadata = { displayName = "Approved role definition ids", description = "Full role definition resource ids principals may be granted." }
        }
      })
      metadata            = { category = "Identity", version = "1.0.0" }
      management_group_id = null
    }
  } : {}

  nsg_hygiene_definitions_cfg = local.nsg_guardrails_enabled ? {
    "nsg-permissive-inbound-rule" = {
      name                = "nsg-permissive-inbound-rule${local.nsg_suffix}"
      display_name        = "NSG rules should not allow inbound traffic from anywhere or to every port"
      description         = "Audits (or denies) NSG security rules that Allow Inbound traffic with a wildcard destination port or a wildcard/Internet source."
      mode                = "All"
      policy_rule         = file("${path.module}/policies/nsg-permissive-inbound-rule.json")
      parameters          = local.governance_effect_parameter
      metadata            = { category = "Network", version = "1.0.0" }
      management_group_id = null
    }
  } : {}

  governance_definitions_cfg = merge(local.rbac_definitions_cfg, local.nsg_hygiene_definitions_cfg)

  governance_expanded = merge(
    {
      for k, d in local.rbac_definitions_cfg : "rbac|${k}" => {
        bare_key             = k
        scope                = var.scope_id
        scope_type           = var.scope_type
        policy_definition_id = azurerm_policy_definition.this[k].id
        name_override        = null
        display_name         = trimspace("${var.baseline_display_name_prefix} ${d.display_name}")
        description          = d.description
        enforce              = true
        not_scopes           = []
        metadata             = null
        overrides            = []
        resource_selectors   = []

        non_compliance_messages = [{
          content                        = replace(var.baseline_non_compliance_message, "{policy}", d.display_name)
          policy_definition_reference_id = null
        }]

        identity                     = null
        identity_role_definition_ids = []
        location                     = var.location

        parameters_json = jsonencode({
          effect                    = { value = local.rbac_effect }
          principalTypes            = { value = local.rbac_principal_types }
          approvedRoleDefinitionIds = { value = local.rbac_approved_definition_ids }
        })

        valid_catalog_key  = true
        target_ok          = true
        effect_ok          = contains(["Audit", "Deny", "Disabled"], local.rbac_effect)
        missing_parameters = toset([])
      }
    },
    {
      for k, d in local.nsg_hygiene_definitions_cfg : "nsghygiene|${k}" => {
        bare_key             = k
        scope                = var.scope_id
        scope_type           = var.scope_type
        policy_definition_id = azurerm_policy_definition.this[k].id
        name_override        = null
        display_name         = trimspace("${var.baseline_display_name_prefix} ${d.display_name}")
        description          = d.description
        enforce              = true
        not_scopes           = []
        metadata             = null
        overrides            = []
        resource_selectors   = []

        non_compliance_messages = [{
          content                        = replace(var.baseline_non_compliance_message, "{policy}", d.display_name)
          policy_definition_reference_id = null
        }]

        identity                     = null
        identity_role_definition_ids = []
        location                     = var.location

        parameters_json = jsonencode({
          effect = { value = local.nsg_effect }
        })

        valid_catalog_key  = true
        target_ok          = true
        effect_ok          = contains(["Audit", "Deny", "Disabled"], local.nsg_effect)
        missing_parameters = toset([])
      }
    },
  )
}

# The guardrail definition keys are reserved; caller policy_definitions entries with the same keys
# would be shadowed.
check "governance_definition_keys_reserved" {
  assert {
    condition     = length(setintersection(toset(keys(var.policy_definitions)), toset(keys(local.governance_definitions_cfg)))) == 0
    error_message = "These policy_definitions keys collide with rbac_guardrails/nsg_guardrails reserved keys and are shadowed: ${join(", ", sort(tolist(setintersection(toset(keys(var.policy_definitions)), toset(keys(local.governance_definitions_cfg))))))}. Rename the caller entries."
  }
}
