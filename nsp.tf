# Network security perimeter guardrails: ready-made CUSTOM policies (no built-ins exist for pinning a
# specific perimeter; the only NSP built-ins ship perimeter diagnostics). The rules live as versioned
# JSON under policies/ and are created and assigned through the module's own engine when
# var.nsp_guardrails is set. Every alias the rules use was verified against the live platform:
# resourceAssociations/accessMode on the association side, and
# networkSecurityPerimeterConfigurations/networkSecurityPerimeter.id on the storage and key vault side.

variable "nsp_guardrails" {
  description = <<DESC
Opt-in network security perimeter guardrails; null (the default) creates nothing. Set to an object
(empty {} is valid) to enable:

- Always: "nsp-association-access-mode", a custom policy flagging NSP resource associations whose
  access mode is not Enforced (Learning observes but does not block). Audit by default because
  Learning is the sanctioned onboarding step; set access_mode_effect = "Deny" to hard-require
  Enforced.
- When approved_perimeter_ids is non-empty: "nsp-storage-perimeter-membership" and
  "nsp-keyvault-perimeter-membership", AuditIfNotExists policies flagging storage accounts / key
  vaults not associated with one of the approved perimeters. Narrow with require_association_for
  (list of "storage_account" / "key_vault", default both).

Optional attributes: access_mode_effect (Audit | Deny | Disabled, default Audit),
approved_perimeter_ids (list of perimeter resource ids), require_association_for,
definition_name_suffix (appended to the definition names, since custom definitions are unique per
subscription; set it when several module calls in one subscription enable these guardrails).
Definitions are created at subscription scope; assignments land at the module scope_id/scope_type.
DESC

  type    = any
  default = null
}

locals {
  nsp_enabled = var.nsp_guardrails != null

  # Attribute reads use a contains(keys()) guard, NOT try(): approved_perimeter_ids routinely holds
  # COMPUTED perimeter ids, and try() over an expression containing unknowns returns a wholly-unknown
  # value, which would poison the definition gating below and blow up the for_each. keys() of the
  # object and the length of the list stay plan-known even when the ids themselves are unknown.
  # (Ternaries only evaluate the taken branch, so the guarded reads are also null-safe on the
  # non-short-circuiting Terraform versions.)
  nsp_attr_keys = local.nsp_enabled ? keys(var.nsp_guardrails) : []

  nsp_access_mode_effect_raw = contains(local.nsp_attr_keys, "access_mode_effect") ? var.nsp_guardrails.access_mode_effect : null
  nsp_access_mode_effect     = local.nsp_access_mode_effect_raw == null ? "Audit" : local.nsp_access_mode_effect_raw

  nsp_approved_ids_raw = contains(local.nsp_attr_keys, "approved_perimeter_ids") ? var.nsp_guardrails.approved_perimeter_ids : null
  nsp_approved_ids     = local.nsp_approved_ids_raw == null ? [] : local.nsp_approved_ids_raw

  nsp_membership_for_raw = contains(local.nsp_attr_keys, "require_association_for") ? var.nsp_guardrails.require_association_for : null
  nsp_membership_for     = local.nsp_membership_for_raw == null ? ["storage_account", "key_vault"] : local.nsp_membership_for_raw

  nsp_suffix_raw = contains(local.nsp_attr_keys, "definition_name_suffix") ? var.nsp_guardrails.definition_name_suffix : null
  nsp_suffix     = local.nsp_suffix_raw == null ? "" : local.nsp_suffix_raw

  # Membership policies are only meaningful with an approved-perimeter list. Their creation is gated
  # on list LENGTH (plan-known even when the ids themselves are computed perimeter ids).
  nsp_membership_enabled = local.nsp_enabled && length(local.nsp_approved_ids) > 0

  nsp_effect_parameter_def = {
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
      metadata      = { displayName = "Effect", description = "The effect of the policy." }
    }
  }
  nsp_membership_parameter_defs = {
    effect = {
      type          = "String"
      allowedValues = ["AuditIfNotExists", "Disabled"]
      defaultValue  = "AuditIfNotExists"
      metadata      = { displayName = "Effect", description = "The effect of the policy." }
    }
    approvedPerimeterIds = {
      type     = "Array"
      metadata = { displayName = "Approved network security perimeters", description = "Resource ids of the perimeters resources must be associated with." }
    }
  }

  # All three guardrails, shaped exactly like definitions_cfg entries, with a gate per key. Built
  # unconditionally then filtered (a ternary whose branches are differently-shaped objects trips
  # Terraform's conditional type unification, a comprehension filter does not).
  nsp_definitions_all = {
    "nsp-association-access-mode" = {
      name                = "nsp-association-access-mode${local.nsp_suffix}"
      display_name        = "NSP associations should use Enforced access mode"
      description         = "Network security perimeter resource associations should use the Enforced access mode; Learning observes traffic but blocks nothing."
      mode                = "All"
      policy_rule         = file("${path.module}/policies/nsp-association-access-mode.json")
      parameters          = local.nsp_effect_parameter_def
      metadata            = { category = "Network", version = "1.0.0" }
      management_group_id = null
    }
    "nsp-storage-perimeter-membership" = {
      name                = "nsp-storage-perimeter-membership${local.nsp_suffix}"
      display_name        = "Storage accounts should be associated with an approved network security perimeter"
      description         = "Audits storage accounts that are not associated with one of the approved network security perimeters."
      mode                = "Indexed"
      policy_rule         = file("${path.module}/policies/nsp-storage-perimeter-membership.json")
      parameters          = local.nsp_membership_parameter_defs
      metadata            = { category = "Network", version = "1.0.0" }
      management_group_id = null
    }
    "nsp-keyvault-perimeter-membership" = {
      name                = "nsp-keyvault-perimeter-membership${local.nsp_suffix}"
      display_name        = "Key vaults should be associated with an approved network security perimeter"
      description         = "Audits key vaults that are not associated with one of the approved network security perimeters."
      mode                = "Indexed"
      policy_rule         = file("${path.module}/policies/nsp-keyvault-perimeter-membership.json")
      parameters          = local.nsp_membership_parameter_defs
      metadata            = { category = "Network", version = "1.0.0" }
      management_group_id = null
    }
  }

  nsp_definition_enabled = {
    "nsp-association-access-mode"       = local.nsp_enabled
    "nsp-storage-perimeter-membership"  = local.nsp_membership_enabled && contains(local.nsp_membership_for, "storage_account")
    "nsp-keyvault-perimeter-membership" = local.nsp_membership_enabled && contains(local.nsp_membership_for, "key_vault")
  }

  nsp_definitions_cfg = { for k, d in local.nsp_definitions_all : k => d if local.nsp_definition_enabled[k] }

  # One assignment per guardrail definition at the module scope, shaped like the internal assignment
  # record so the engine's routing, naming, and preconditions apply unchanged.
  nsp_expanded = {
    for k, d in local.nsp_definitions_cfg : "nsp|${k}" => {
      bare_key             = k
      scope                = var.scope_id
      scope_type           = var.scope_type
      policy_definition_id = azurerm_policy_definition.this[k].id
      name_override        = null
      display_name         = trimspace("${local.authored_display_prefix} ${d.display_name}")
      description          = d.description
      enforce              = true
      not_scopes           = []
      metadata             = null
      overrides            = []
      resource_selectors   = []

      non_compliance_messages = [{
        content                        = replace(local.authored_non_compliance_template, "{policy}", d.display_name)
        policy_definition_reference_id = null
      }]

      identity                     = null
      identity_role_definition_ids = []
      location                     = var.location

      parameters_json = k == "nsp-association-access-mode" ? jsonencode({
        effect = { value = local.nsp_access_mode_effect }
        }) : jsonencode({
        approvedPerimeterIds = { value = local.nsp_approved_ids }
      })

      valid_catalog_key  = true
      target_ok          = true
      effect_ok          = contains(["Audit", "Deny", "Disabled"], local.nsp_access_mode_effect)
      missing_parameters = toset([])
    }
  }
}

# The nsp guardrail definition keys are reserved; a caller policy_definitions entry with the same key
# would be shadowed by the guardrail definition.
check "nsp_definition_keys_reserved" {
  assert {
    condition     = length(setintersection(toset(keys(var.policy_definitions)), toset(keys(local.nsp_definitions_cfg)))) == 0
    error_message = "These policy_definitions keys collide with nsp_guardrails reserved keys and are shadowed: ${join(", ", sort(tolist(setintersection(toset(keys(var.policy_definitions)), toset(keys(local.nsp_definitions_cfg))))))}. Rename the caller entries."
  }
}
