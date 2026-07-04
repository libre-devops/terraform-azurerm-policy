# Resource group lock guardrails: a ready-made CUSTOM DeployIfNotExists policy (no built-in locks
# resources by tag) that keeps management locks on business-critical resource groups. One
# parameterised definition (policies/resource-group-lock-by-tag.json), assigned twice: a ReadOnly
# lock for the critical tag values and a CanNotDelete lock for the production tag values. The
# assignments carry a system-assigned identity granted User Access Administrator at the assignment
# scope THROUGH THE ENGINE'S EXISTING GRANT MACHINERY, so the role assignment exists only when the
# guardrail itself does.

variable "rg_lock_guardrails" {
  description = <<DESC
Opt-in resource group lock guardrails; null (the default) creates nothing. Set to an object
(empty {} is valid) to enable a DeployIfNotExists policy that keeps a management lock on resource
groups carrying a business-criticality tag: ReadOnly where the tag holds one of
readonly_tag_values (default ["Critical"]) and CanNotDelete where it holds one of
cannotdelete_tag_values (default ["Production"]).

Optional attributes: tag_name (default "BusinessLevel"), readonly_tag_values,
cannotdelete_tag_values (set either to [] to drop that half), effect (DeployIfNotExists |
AuditIfNotExists | Disabled, default DeployIfNotExists; AuditIfNotExists reports the missing lock
without creating it), lock_notes (the note stamped on created locks), and definition_name_suffix
(custom definitions are unique per subscription; set it when several module calls in one
subscription enable this guardrail).

The DeployIfNotExists remediation runs as a system-assigned identity granted User Access
Administrator at the assignment scope (locks live under Microsoft.Authorization); that grant is
created only alongside the assignment. Remember locks cut both ways: a ReadOnly lock blocks
PUT/PATCH/DELETE on everything in the group, including your own pipelines, and Terraform destroys
of locked groups fail until the lock is removed by someone with lock-write rights.
DESC

  type    = any
  default = null
}

locals {
  rg_locks_enabled = var.rg_lock_guardrails != null

  # contains(keys()) guards, not try(): see the NSP guardrails note on unknown-poisoning.
  rg_locks_attr_keys = local.rg_locks_enabled ? keys(var.rg_lock_guardrails) : []

  rg_locks_tag_name_raw = contains(local.rg_locks_attr_keys, "tag_name") ? var.rg_lock_guardrails.tag_name : null
  rg_locks_tag_name     = local.rg_locks_tag_name_raw == null ? "BusinessLevel" : local.rg_locks_tag_name_raw

  rg_locks_readonly_values_raw = contains(local.rg_locks_attr_keys, "readonly_tag_values") ? var.rg_lock_guardrails.readonly_tag_values : null
  rg_locks_readonly_values     = local.rg_locks_readonly_values_raw == null ? ["Critical"] : local.rg_locks_readonly_values_raw

  rg_locks_cannotdelete_values_raw = contains(local.rg_locks_attr_keys, "cannotdelete_tag_values") ? var.rg_lock_guardrails.cannotdelete_tag_values : null
  rg_locks_cannotdelete_values     = local.rg_locks_cannotdelete_values_raw == null ? ["Production"] : local.rg_locks_cannotdelete_values_raw

  rg_locks_effect_raw = contains(local.rg_locks_attr_keys, "effect") ? var.rg_lock_guardrails.effect : null
  rg_locks_effect     = local.rg_locks_effect_raw == null ? "DeployIfNotExists" : local.rg_locks_effect_raw

  rg_locks_notes_raw = contains(local.rg_locks_attr_keys, "lock_notes") ? var.rg_lock_guardrails.lock_notes : null
  rg_locks_notes     = local.rg_locks_notes_raw == null ? "Kept by the resource group lock guardrail policy; remove the tag (or exempt the assignment) before removing the lock." : local.rg_locks_notes_raw

  rg_locks_suffix_raw = contains(local.rg_locks_attr_keys, "definition_name_suffix") ? var.rg_lock_guardrails.definition_name_suffix : null
  rg_locks_suffix     = local.rg_locks_suffix_raw == null ? "" : local.rg_locks_suffix_raw

  rg_locks_parameter_defs = {
    effect = {
      type          = "String"
      allowedValues = ["DeployIfNotExists", "AuditIfNotExists", "Disabled"]
      defaultValue  = "DeployIfNotExists"
      metadata      = { displayName = "Effect", description = "The effect of the policy." }
    }
    tagName = {
      type     = "String"
      metadata = { displayName = "Tag name", description = "The business-criticality tag inspected on resource groups." }
    }
    tagValues = {
      type     = "Array"
      metadata = { displayName = "Tag values", description = "Tag values that require the lock level." }
    }
    lockLevel = {
      type          = "String"
      allowedValues = ["ReadOnly", "CanNotDelete"]
      metadata      = { displayName = "Lock level", description = "The management lock level kept on matching resource groups." }
    }
    lockNotes = {
      type     = "String"
      metadata = { displayName = "Lock notes", description = "The note stamped on locks the policy creates." }
    }
  }

  rg_locks_definitions_cfg = local.rg_locks_enabled ? {
    "rg-lock-by-tag" = {
      name                = "rg-lock-by-tag${local.rg_locks_suffix}"
      display_name        = "Resource groups tagged business-critical should keep a management lock"
      description         = "Deploys (or audits for) a management lock on resource groups whose business-criticality tag matches the configured values: ReadOnly for the critical values, CanNotDelete for the production values."
      mode                = "All"
      policy_rule         = file("${path.module}/policies/resource-group-lock-by-tag.json")
      parameters          = local.rg_locks_parameter_defs
      metadata            = { category = "General", version = "1.0.0" }
      management_group_id = null
    }
  } : {}

  rg_locks_levels = {
    readonly     = { lock_level = "ReadOnly", tag_values = local.rg_locks_readonly_values, label = "ReadOnly" }
    cannotdelete = { lock_level = "CanNotDelete", tag_values = local.rg_locks_cannotdelete_values, label = "CanNotDelete" }
  }

  rg_locks_expanded = {
    for k, lvl in local.rg_locks_levels : "rglock|${k}" => {
      bare_key             = "rg-lock-${k}"
      scope                = var.scope_id
      scope_type           = var.scope_type
      policy_definition_id = azurerm_policy_definition.this["rg-lock-by-tag"].id
      name_override        = null
      display_name         = trimspace("${local.authored_display_prefix} ${lvl.label} lock on ${local.rg_locks_tag_name} = ${join("/", lvl.tag_values)} resource groups")
      description          = "Keeps a ${lvl.label} management lock on resource groups whose ${local.rg_locks_tag_name} tag is one of: ${join(", ", lvl.tag_values)}."
      enforce              = true
      not_scopes           = []
      metadata             = null
      overrides            = []
      resource_selectors   = []

      non_compliance_messages = [{
        content                        = replace(local.authored_non_compliance_template, "{policy}", "${lvl.label} lock on business-critical resource groups")
        policy_definition_reference_id = null
      }]

      # The engine grants these roles to the assignment identity AT the assignment scope, and only
      # while the assignment exists: enabling the guardrail is what creates the grant.
      identity                     = { type = "SystemAssigned", identity_ids = null }
      identity_role_definition_ids = ["18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"]
      location                     = var.location

      parameters_json = jsonencode({
        effect    = { value = local.rg_locks_effect }
        tagName   = { value = local.rg_locks_tag_name }
        tagValues = { value = lvl.tag_values }
        lockLevel = { value = lvl.lock_level }
        lockNotes = { value = local.rg_locks_notes }
      })

      valid_catalog_key  = true
      target_ok          = true
      effect_ok          = contains(["DeployIfNotExists", "AuditIfNotExists", "Disabled"], local.rg_locks_effect)
      missing_parameters = toset([])
    } if local.rg_locks_enabled && length(lvl.tag_values) > 0
  }
}

# The guardrail definition key is reserved; a caller policy_definitions entry with the same key
# would be shadowed.
check "rg_lock_definition_key_reserved" {
  assert {
    condition     = !contains(keys(var.policy_definitions), "rg-lock-by-tag") || !local.rg_locks_enabled
    error_message = "The policy_definitions key \"rg-lock-by-tag\" collides with the rg_lock_guardrails reserved key and is shadowed. Rename the caller entry."
  }
}
