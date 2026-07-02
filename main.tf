# Custom policy definitions. policy_rule / parameters / metadata accept an HCL object (encoded here)
# or a pre-rendered JSON string, so rules can live inline or in versioned .json files.
resource "azurerm_policy_definition" "this" {
  for_each = local.definitions_cfg

  name                = each.value.name
  policy_type         = "Custom"
  mode                = each.value.mode
  display_name        = each.value.display_name
  description         = each.value.description
  management_group_id = each.value.management_group_id

  policy_rule = each.value.policy_rule == null ? null : try(tostring(each.value.policy_rule), jsonencode(each.value.policy_rule))
  parameters  = each.value.parameters == null ? null : try(tostring(each.value.parameters), jsonencode(each.value.parameters))
  metadata    = each.value.metadata == null ? null : try(tostring(each.value.metadata), jsonencode(each.value.metadata))

  lifecycle {
    precondition {
      condition     = each.value.policy_rule != null
      error_message = "policy_definitions \"${each.key}\" must set policy_rule (an HCL object or a JSON string)."
    }
  }
}

# Custom initiatives. References resolve either a literal policy id (built-in or external) or a key of
# the custom definitions above. Subscription-scope sets use the classic resource; management-group
# sets use the dedicated resource (the classic management_group_id argument is deprecated in 4.x).
resource "azurerm_policy_set_definition" "this" {
  for_each = local.sets_sub

  name         = each.value.name
  policy_type  = "Custom"
  display_name = each.value.display_name
  description  = each.value.description

  parameters = each.value.parameters == null ? null : try(tostring(each.value.parameters), jsonencode(each.value.parameters))
  metadata   = each.value.metadata == null ? null : try(tostring(each.value.metadata), jsonencode(each.value.metadata))

  dynamic "policy_definition_reference" {
    for_each = each.value.policy_definition_references
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id != null ? policy_definition_reference.value.policy_definition_id : try(azurerm_policy_definition.this[policy_definition_reference.value.definition_key].id, null)
      parameter_values     = policy_definition_reference.value.parameter_values == null ? null : try(tostring(policy_definition_reference.value.parameter_values), jsonencode(policy_definition_reference.value.parameter_values))
      reference_id         = policy_definition_reference.value.reference_id
      policy_group_names   = policy_definition_reference.value.policy_group_names
    }
  }

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups
    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      category                        = policy_definition_group.value.category
      description                     = policy_definition_group.value.description
      additional_metadata_resource_id = policy_definition_group.value.additional_metadata_resource_id
    }
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for r in each.value.policy_definition_references :
        (r.policy_definition_id == null) != (r.definition_key == null) &&
        (r.definition_key == null || contains(keys(var.policy_definitions), coalesce(r.definition_key, "-")))
      ])
      error_message = "Each reference in policy_set_definitions \"${each.key}\" must set exactly one of policy_definition_id or definition_key, and any definition_key must exist in policy_definitions."
    }
  }
}

resource "azurerm_management_group_policy_set_definition" "this" {
  for_each = local.sets_mg

  name                = each.value.name
  policy_type         = "Custom"
  display_name        = each.value.display_name
  description         = each.value.description
  management_group_id = each.value.management_group_id

  parameters = each.value.parameters == null ? null : try(tostring(each.value.parameters), jsonencode(each.value.parameters))
  metadata   = each.value.metadata == null ? null : try(tostring(each.value.metadata), jsonencode(each.value.metadata))

  dynamic "policy_definition_reference" {
    for_each = each.value.policy_definition_references
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id != null ? policy_definition_reference.value.policy_definition_id : try(azurerm_policy_definition.this[policy_definition_reference.value.definition_key].id, null)
      parameter_values     = policy_definition_reference.value.parameter_values == null ? null : try(tostring(policy_definition_reference.value.parameter_values), jsonencode(policy_definition_reference.value.parameter_values))
      reference_id         = policy_definition_reference.value.reference_id
      policy_group_names   = policy_definition_reference.value.policy_group_names
    }
  }

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups
    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      category                        = policy_definition_group.value.category
      description                     = policy_definition_group.value.description
      additional_metadata_resource_id = policy_definition_group.value.additional_metadata_resource_id
    }
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for r in each.value.policy_definition_references :
        (r.policy_definition_id == null) != (r.definition_key == null) &&
        (r.definition_key == null || contains(keys(var.policy_definitions), coalesce(r.definition_key, "-")))
      ])
      error_message = "Each reference in policy_set_definitions \"${each.key}\" must set exactly one of policy_definition_id or definition_key, and any definition_key must exist in policy_definitions."
    }
  }
}

# ---------- Assignments ----------
# One resource per scope type; local.assignments_all is routed by the detected scope. The four bodies
# are intentionally identical apart from the scope argument.

resource "azurerm_management_group_policy_assignment" "this" {
  for_each = local.assignments_mg

  management_group_id  = each.value.scope
  name                 = local.assignment_name[each.key]
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name == null ? null : substr(each.value.display_name, 0, 128)
  description          = each.value.description
  parameters           = each.value.parameters_json
  enforce              = each.value.enforce
  not_scopes           = each.value.not_scopes
  metadata             = each.value.metadata
  location             = each.value.identity != null ? each.value.location : null

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.valid_catalog_key
      error_message = "baseline_policies key \"${each.value.bare_key}\" is not in the catalog. Valid keys: ${join(", ", sort(keys(local.baseline_catalog)))}."
    }
    precondition {
      condition     = each.value.effect_ok
      error_message = "The effect set on baseline_policies \"${each.value.bare_key}\" is not accepted by that definition (fixed-effect definitions accept no override)."
    }
    precondition {
      condition     = each.value.target_ok
      error_message = "Assignment \"${each.value.bare_key}\" must set exactly one of policy_definition_id, definition_key, or set_definition_key, and any referenced key must exist in this module call."
    }
    precondition {
      condition     = length(each.value.missing_parameters) == 0
      error_message = "baseline_policies \"${each.value.bare_key}\" is missing required parameters: ${join(", ", sort(tolist(each.value.missing_parameters)))}."
    }
    precondition {
      condition     = each.value.identity == null || each.value.location != null
      error_message = "Assignment \"${each.value.bare_key}\" carries an identity, so a location is required (set the module-level location)."
    }
  }
}

resource "azurerm_subscription_policy_assignment" "this" {
  for_each = local.assignments_sub

  subscription_id      = each.value.scope
  name                 = local.assignment_name[each.key]
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name == null ? null : substr(each.value.display_name, 0, 128)
  description          = each.value.description
  parameters           = each.value.parameters_json
  enforce              = each.value.enforce
  not_scopes           = each.value.not_scopes
  metadata             = each.value.metadata
  location             = each.value.identity != null ? each.value.location : null

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.scope != null
      error_message = "Assignment \"${each.value.bare_key}\" has no scope: set the module-level scope_id or a per-entry scope_id."
    }
    precondition {
      condition     = contains(["subscription", "none"], local.assignment_scope_type[each.key])
      error_message = "Assignment \"${each.value.bare_key}\" has an unrecognized scope_type \"${local.assignment_scope_type[each.key]}\": use management_group, subscription, resource_group, or resource."
    }
    precondition {
      condition     = each.value.target_ok
      error_message = "Assignment \"${each.value.bare_key}\" must set exactly one of policy_definition_id, definition_key, or set_definition_key, and any referenced key must exist in this module call."
    }
    precondition {
      condition     = each.value.valid_catalog_key
      error_message = "baseline_policies key \"${each.value.bare_key}\" is not in the catalog. Valid keys: ${join(", ", sort(keys(local.baseline_catalog)))}."
    }
    precondition {
      condition     = each.value.effect_ok
      error_message = "The effect set on baseline_policies \"${each.value.bare_key}\" is not accepted by that definition (fixed-effect definitions accept no override)."
    }
    precondition {
      condition     = length(each.value.missing_parameters) == 0
      error_message = "baseline_policies \"${each.value.bare_key}\" is missing required parameters: ${join(", ", sort(tolist(each.value.missing_parameters)))}."
    }
    precondition {
      condition     = each.value.identity == null || each.value.location != null
      error_message = "Assignment \"${each.value.bare_key}\" carries an identity, so a location is required (set the module-level location)."
    }
  }
}

resource "azurerm_resource_group_policy_assignment" "this" {
  for_each = local.assignments_rg

  resource_group_id    = each.value.scope
  name                 = local.assignment_name[each.key]
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name == null ? null : substr(each.value.display_name, 0, 128)
  description          = each.value.description
  parameters           = each.value.parameters_json
  enforce              = each.value.enforce
  not_scopes           = each.value.not_scopes
  metadata             = each.value.metadata
  location             = each.value.identity != null ? each.value.location : null

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.valid_catalog_key
      error_message = "baseline_policies key \"${each.value.bare_key}\" is not in the catalog. Valid keys: ${join(", ", sort(keys(local.baseline_catalog)))}."
    }
    precondition {
      condition     = each.value.effect_ok
      error_message = "The effect set on baseline_policies \"${each.value.bare_key}\" is not accepted by that definition (fixed-effect definitions accept no override)."
    }
    precondition {
      condition     = each.value.target_ok
      error_message = "Assignment \"${each.value.bare_key}\" must set exactly one of policy_definition_id, definition_key, or set_definition_key, and any referenced key must exist in this module call."
    }
    precondition {
      condition     = length(each.value.missing_parameters) == 0
      error_message = "baseline_policies \"${each.value.bare_key}\" is missing required parameters: ${join(", ", sort(tolist(each.value.missing_parameters)))}."
    }
    precondition {
      condition     = each.value.identity == null || each.value.location != null
      error_message = "Assignment \"${each.value.bare_key}\" carries an identity, so a location is required (set the module-level location)."
    }
  }
}

resource "azurerm_resource_policy_assignment" "this" {
  for_each = local.assignments_resource

  resource_id          = each.value.scope
  name                 = local.assignment_name[each.key]
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name == null ? null : substr(each.value.display_name, 0, 128)
  description          = each.value.description
  parameters           = each.value.parameters_json
  enforce              = each.value.enforce
  not_scopes           = each.value.not_scopes
  metadata             = each.value.metadata
  location             = each.value.identity != null ? each.value.location : null

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.valid_catalog_key
      error_message = "baseline_policies key \"${each.value.bare_key}\" is not in the catalog. Valid keys: ${join(", ", sort(keys(local.baseline_catalog)))}."
    }
    precondition {
      condition     = each.value.effect_ok
      error_message = "The effect set on baseline_policies \"${each.value.bare_key}\" is not accepted by that definition (fixed-effect definitions accept no override)."
    }
    precondition {
      condition     = each.value.target_ok
      error_message = "Assignment \"${each.value.bare_key}\" must set exactly one of policy_definition_id, definition_key, or set_definition_key, and any referenced key must exist in this module call."
    }
    precondition {
      condition     = length(each.value.missing_parameters) == 0
      error_message = "baseline_policies \"${each.value.bare_key}\" is missing required parameters: ${join(", ", sort(tolist(each.value.missing_parameters)))}."
    }
    precondition {
      condition     = each.value.identity == null || each.value.location != null
      error_message = "Assignment \"${each.value.bare_key}\" carries an identity, so a location is required (set the module-level location)."
    }
  }
}

# Role grants for identity-bearing assignments (Modify / DeployIfNotExists): each required role is
# granted to the assignment's managed identity at the assignment scope, so remediation can act there.
resource "azurerm_role_assignment" "policy_identity" {
  for_each = local.identity_role_grants

  scope              = each.value.scope
  role_definition_id = each.value.role_id
  principal_id = (
    local.assignment_scope_type[each.value.assignment_key] == "management_group" ? azurerm_management_group_policy_assignment.this[each.value.assignment_key].identity[0].principal_id :
    local.assignment_scope_type[each.value.assignment_key] == "resource_group" ? azurerm_resource_group_policy_assignment.this[each.value.assignment_key].identity[0].principal_id :
    local.assignment_scope_type[each.value.assignment_key] == "resource" ? azurerm_resource_policy_assignment.this[each.value.assignment_key].identity[0].principal_id :
    azurerm_subscription_policy_assignment.this[each.value.assignment_key].identity[0].principal_id
  )
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Grants the policy assignment's managed identity the role its Modify/DeployIfNotExists definition requires."
}

# ---------- Exemptions ----------
# The exempted assignment id is resolved from a literal id or from this module call's assignments; the
# scope string routes each exemption to the matching resource, mirroring the assignments above.

resource "azurerm_management_group_policy_exemption" "this" {
  for_each = local.exemptions_mg

  management_group_id = each.value.scope
  name                = each.value.name
  policy_assignment_id = each.value.policy_assignment_id != null ? each.value.policy_assignment_id : try(
    local.assignment_scope_type[each.value.internal_key] == "management_group" ? azurerm_management_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource_group" ? azurerm_resource_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource" ? azurerm_resource_policy_assignment.this[each.value.internal_key].id :
    azurerm_subscription_policy_assignment.this[each.value.internal_key].id
  , null)
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata

  lifecycle {
    precondition {
      condition     = each.value.internal_key_ok
      error_message = "Exemption \"${each.key}\" references an assignment_key or baseline_key that does not exist in this module call."
    }
  }
}

resource "azurerm_subscription_policy_exemption" "this" {
  for_each = local.exemptions_sub

  subscription_id = each.value.scope
  name            = each.value.name
  policy_assignment_id = each.value.policy_assignment_id != null ? each.value.policy_assignment_id : try(
    local.assignment_scope_type[each.value.internal_key] == "management_group" ? azurerm_management_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource_group" ? azurerm_resource_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource" ? azurerm_resource_policy_assignment.this[each.value.internal_key].id :
    azurerm_subscription_policy_assignment.this[each.value.internal_key].id
  , null)
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata

  lifecycle {
    precondition {
      condition     = each.value.scope != null
      error_message = "Exemption \"${each.key}\" has no scope: set the module-level scope_id or a per-entry scope_id."
    }
    precondition {
      condition     = contains(["subscription", "none"], local.exemption_scope_type[each.key])
      error_message = "Exemption \"${each.key}\" has an unrecognized scope_type \"${local.exemption_scope_type[each.key]}\": use management_group, subscription, resource_group, or resource."
    }
    precondition {
      condition     = each.value.internal_key_ok
      error_message = "Exemption \"${each.key}\" references an assignment_key or baseline_key that does not exist in this module call."
    }
  }
}

resource "azurerm_resource_group_policy_exemption" "this" {
  for_each = local.exemptions_rg

  resource_group_id = each.value.scope
  name              = each.value.name
  policy_assignment_id = each.value.policy_assignment_id != null ? each.value.policy_assignment_id : try(
    local.assignment_scope_type[each.value.internal_key] == "management_group" ? azurerm_management_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource_group" ? azurerm_resource_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource" ? azurerm_resource_policy_assignment.this[each.value.internal_key].id :
    azurerm_subscription_policy_assignment.this[each.value.internal_key].id
  , null)
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata

  lifecycle {
    precondition {
      condition     = each.value.internal_key_ok
      error_message = "Exemption \"${each.key}\" references an assignment_key or baseline_key that does not exist in this module call."
    }
  }
}

resource "azurerm_resource_policy_exemption" "this" {
  for_each = local.exemptions_resource

  resource_id = each.value.scope
  name        = each.value.name
  policy_assignment_id = each.value.policy_assignment_id != null ? each.value.policy_assignment_id : try(
    local.assignment_scope_type[each.value.internal_key] == "management_group" ? azurerm_management_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource_group" ? azurerm_resource_group_policy_assignment.this[each.value.internal_key].id :
    local.assignment_scope_type[each.value.internal_key] == "resource" ? azurerm_resource_policy_assignment.this[each.value.internal_key].id :
    azurerm_subscription_policy_assignment.this[each.value.internal_key].id
  , null)
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata

  lifecycle {
    precondition {
      condition     = each.value.internal_key_ok
      error_message = "Exemption \"${each.key}\" references an assignment_key or baseline_key that does not exist in this module call."
    }
  }
}
