locals {
  valid_scope_types = ["management_group", "subscription", "resource_group", "resource"]

  # A placeholder catalog entry substituted when a baseline key does not exist, so the expansion below
  # never errors mid-expression and the resource precondition can fail the plan with a readable
  # message instead (valid_catalog_key carries the verdict).
  baseline_catalog_fallback = {
    policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000000"
    is_set                       = false
    display_name                 = "(unknown catalog key)"
    category                     = "Unknown"
    description                  = "(unknown catalog key)"
    effect_parameter             = null
    allowed_effects              = []
    default_effect               = null
    default_parameters           = {}
    required_parameters          = []
    default_enforce              = true
    identity_role_definition_ids = []
  }

  # ---------- Input normalization ----------
  # The object-map variables are typed `any` (their parameter shapes differ per entry, which map(object)
  # cannot express), so every attribute is read with try() and given its default here. The
  # try(coalesce(x), default) pattern covers both a missing attribute and an explicit null.

  baseline_cfg = {
    for k, raw in var.baseline_policies : k => {
      effect                 = try(raw.effect, null)
      parameters             = try(coalesce(raw.parameters), {})
      enforce                = try(raw.enforce, null)
      scope_id               = try(raw.scope_id, null)
      scope_type             = try(raw.scope_type, null)
      non_compliance_message = try(raw.non_compliance_message, null)
      not_scopes             = try(coalesce(raw.not_scopes), [])
      display_name           = try(raw.display_name, null)
      description            = try(raw.description, null)
    }
  }

  # Caller definitions plus the nsp_guardrails definitions (see nsp.tf); the guardrail keys are
  # reserved and win a collision (a check block surfaces any shadowed caller entry).
  definitions_cfg = merge(
    {
      for k, raw in var.policy_definitions : k => {
        name                = try(raw.name, k)
        display_name        = try(raw.display_name, k)
        description         = try(raw.description, null)
        mode                = try(coalesce(raw.mode), "All")
        policy_rule         = try(raw.policy_rule, null)
        parameters          = try(raw.parameters, null)
        metadata            = try(raw.metadata, null)
        management_group_id = try(raw.management_group_id, null)
      }
    },
    local.nsp_definitions_cfg,
  )

  set_definitions_cfg = {
    for k, raw in var.policy_set_definitions : k => {
      name                = try(raw.name, k)
      display_name        = try(raw.display_name, k)
      description         = try(raw.description, null)
      parameters          = try(raw.parameters, null)
      metadata            = try(raw.metadata, null)
      management_group_id = try(raw.management_group_id, null)

      policy_definition_references = [
        for r in try(coalesce(raw.policy_definition_references), []) : {
          policy_definition_id = try(r.policy_definition_id, null)
          definition_key       = try(r.definition_key, null)
          parameter_values     = try(r.parameter_values, null)
          reference_id         = try(r.reference_id, null)
          policy_group_names   = try(r.policy_group_names, null)
        }
      ]

      policy_definition_groups = [
        for g in try(coalesce(raw.policy_definition_groups), []) : {
          name                            = g.name
          display_name                    = try(g.display_name, null)
          category                        = try(g.category, null)
          description                     = try(g.description, null)
          additional_metadata_resource_id = try(g.additional_metadata_resource_id, null)
        }
      ]
    }
  }

  sets_sub = { for k, sd in local.set_definitions_cfg : k => sd if sd.management_group_id == null }
  sets_mg  = { for k, sd in local.set_definitions_cfg : k => sd if sd.management_group_id != null }

  assignments_cfg = {
    for k, raw in var.policy_assignments : k => {
      name                 = try(raw.name, null)
      scope_id             = try(raw.scope_id, null)
      scope_type           = try(raw.scope_type, null)
      policy_definition_id = try(raw.policy_definition_id, null)
      definition_key       = try(raw.definition_key, null)
      set_definition_key   = try(raw.set_definition_key, null)

      display_name = try(raw.display_name, null)
      description  = try(raw.description, null)
      parameters   = try(raw.parameters, null)
      metadata     = try(raw.metadata, null)
      enforce      = try(coalesce(raw.enforce), true)
      not_scopes   = try(coalesce(raw.not_scopes), [])
      location     = try(raw.location, null)

      non_compliance_messages = [
        for m in try(coalesce(raw.non_compliance_messages), []) : {
          content                        = m.content
          policy_definition_reference_id = try(m.policy_definition_reference_id, null)
        }
      ]

      identity = try(raw.identity, null) == null ? null : {
        type         = raw.identity.type
        identity_ids = try(raw.identity.identity_ids, null)
      }
      identity_role_definition_ids = try(coalesce(raw.identity_role_definition_ids), [])

      overrides = [
        for o in try(coalesce(raw.overrides), []) : {
          value = o.value
          selectors = [
            for s in try(coalesce(o.selectors), []) : {
              in     = try(s.in, null)
              not_in = try(s.not_in, null)
            }
          ]
        }
      ]

      resource_selectors = [
        for rs in try(coalesce(raw.resource_selectors), []) : {
          name = try(rs.name, null)
          selectors = [
            for s in rs.selectors : {
              kind   = s.kind
              in     = try(s.in, null)
              not_in = try(s.not_in, null)
            }
          ]
        }
      ]
    }
  }

  exemptions_cfg = {
    for k, raw in var.policy_exemptions : k => {
      name                 = try(raw.name, k)
      scope_id             = try(raw.scope_id, null)
      scope_type           = try(raw.scope_type, null)
      policy_assignment_id = try(raw.policy_assignment_id, null)
      assignment_key       = try(raw.assignment_key, null)
      baseline_key         = try(raw.baseline_key, null)

      exemption_category              = try(coalesce(raw.exemption_category), "Waiver")
      display_name                    = try(raw.display_name, null)
      description                     = try(raw.description, null)
      expires_on                      = try(raw.expires_on, null)
      policy_definition_reference_ids = try(raw.policy_definition_reference_ids, null)
      metadata                        = try(raw.metadata, null)
    }
  }

  # ---------- Baseline expansion ----------
  # Each baseline_policies entry becomes one normalized assignment, internal key "baseline|<key>".
  # Caller parameters are plain values (merged over the catalog defaults) and are wrapped into the
  # ARM assignment parameter format ({"name": {"value": ...}}) here; the chosen effect is injected
  # through the definition's effect parameter when it has one.
  baseline_catalog_effective = {
    for k, cfg in local.baseline_cfg : k => lookup(local.baseline_catalog, k, local.baseline_catalog_fallback)
  }

  baseline_parameters_wrapped = {
    for k, cfg in local.baseline_cfg : k => merge(
      { for pk, pv in merge(local.baseline_catalog_effective[k].default_parameters, cfg.parameters) : pk => { value = pv } },
      (local.baseline_catalog_effective[k].effect_parameter != null && (cfg.effect != null || local.baseline_catalog_effective[k].default_effect != null)) ? {
        (coalesce(local.baseline_catalog_effective[k].effect_parameter, "effect")) = {
          value = coalesce(cfg.effect, local.baseline_catalog_effective[k].default_effect)
        }
      } : {}
    )
  }

  baseline_expanded = {
    for k, cfg in local.baseline_cfg : "baseline|${k}" => {
      bare_key             = k
      scope                = try(coalesce(cfg.scope_id, var.scope_id), null)
      scope_type           = cfg.scope_type != null ? cfg.scope_type : (cfg.scope_id == null ? var.scope_type : null)
      policy_definition_id = local.baseline_catalog_effective[k].policy_id
      name_override        = null
      display_name         = coalesce(cfg.display_name, trimspace("${var.baseline_display_name_prefix} ${local.baseline_catalog_effective[k].display_name}"))
      description          = coalesce(cfg.description, local.baseline_catalog_effective[k].description)
      enforce              = coalesce(cfg.enforce, local.baseline_catalog_effective[k].default_enforce)
      not_scopes           = cfg.not_scopes
      metadata             = null
      overrides            = []
      resource_selectors   = []

      non_compliance_messages = [{
        content                        = coalesce(cfg.non_compliance_message, replace(var.baseline_non_compliance_message, "{policy}", local.baseline_catalog_effective[k].display_name))
        policy_definition_reference_id = null
      }]

      identity = length(local.baseline_catalog_effective[k].identity_role_definition_ids) > 0 ? {
        type         = "SystemAssigned"
        identity_ids = null
      } : null
      identity_role_definition_ids = local.baseline_catalog_effective[k].identity_role_definition_ids
      location                     = var.location

      parameters_json = length(local.baseline_parameters_wrapped[k]) > 0 ? jsonencode(local.baseline_parameters_wrapped[k]) : null

      # Precondition payloads (evaluated here so the resources can assert with clear messages).
      valid_catalog_key = contains(keys(local.baseline_catalog), k)
      target_ok         = true
      effect_ok = cfg.effect == null ? true : (
        local.baseline_catalog_effective[k].effect_parameter != null &&
        contains(local.baseline_catalog_effective[k].allowed_effects, cfg.effect)
      )
      missing_parameters = setsubtract(
        toset(local.baseline_catalog_effective[k].required_parameters),
        toset(keys(merge(local.baseline_catalog_effective[k].default_parameters, cfg.parameters)))
      )
    }
  }

  # ---------- Engine assignment normalization ----------
  # Custom assignments take the same internal shape, key "custom|<key>". The target id is resolved
  # from the literal id or from this module call's definitions/sets; those ids are computed at apply,
  # which is fine because they only ever appear in map VALUES (never in for_each keys). try() guards
  # the index so a bad key fails through the precondition, not a raw index error.
  custom_expanded = {
    for k, a in local.assignments_cfg : "custom|${k}" => {
      bare_key   = k
      scope      = try(coalesce(a.scope_id, var.scope_id), null)
      scope_type = a.scope_type != null ? a.scope_type : (a.scope_id == null ? var.scope_type : null)
      policy_definition_id = (
        a.policy_definition_id != null ? a.policy_definition_id :
        a.definition_key != null ? try(azurerm_policy_definition.this[a.definition_key].id, null) :
        try(azurerm_policy_set_definition.this[a.set_definition_key].id, azurerm_management_group_policy_set_definition.this[a.set_definition_key].id, null)
      )
      name_override      = a.name
      display_name       = a.display_name
      description        = a.description
      enforce            = a.enforce
      not_scopes         = a.not_scopes
      metadata           = a.metadata == null ? null : try(tostring(a.metadata), jsonencode(a.metadata))
      overrides          = a.overrides
      resource_selectors = a.resource_selectors

      non_compliance_messages = a.non_compliance_messages

      identity                     = a.identity
      identity_role_definition_ids = a.identity_role_definition_ids
      location                     = try(coalesce(a.location, var.location), null)

      valid_catalog_key = true
      # coalesce sentinels keep the contains() operands non-null: Terraform does not short-circuit
      # || on all versions, so the right side must evaluate safely even when the key is null.
      target_ok = (
        length([for t in [a.policy_definition_id, a.definition_key, a.set_definition_key] : t if t != null]) == 1 &&
        (a.definition_key == null || contains(keys(var.policy_definitions), coalesce(a.definition_key, "-"))) &&
        (a.set_definition_key == null || contains(keys(var.policy_set_definitions), coalesce(a.set_definition_key, "-")))
      )
      effect_ok          = true
      missing_parameters = toset([])

      # Plain parameter values are wrapped into the ARM assignment format; a string passes through
      # as pre-rendered JSON.
      parameters_json = a.parameters == null ? null : (
        can(tostring(a.parameters)) ? tostring(a.parameters) : jsonencode({ for pk, pv in a.parameters : pk => { value = pv } })
      )
    }
  }

  assignments_all = merge(local.baseline_expanded, local.custom_expanded, local.nsp_expanded)

  # ---------- Scope routing ----------
  # An explicit scope_type wins; otherwise the scope string decides which azurerm resource an
  # assignment or exemption lands on. A computed scope id cannot be inspected at plan time, which is
  # exactly what the explicit scope_type is for.
  assignment_scope_type = {
    for k, a in local.assignments_all : k => (
      a.scope_type != null ? a.scope_type :
      a.scope == null ? "none" :
      startswith(lower(a.scope), "/providers/microsoft.management/managementgroups/") ? "management_group" :
      length(regexall("^/subscriptions/[^/]+$", lower(a.scope))) > 0 ? "subscription" :
      length(regexall("^/subscriptions/[^/]+/resourcegroups/[^/]+$", lower(a.scope))) > 0 ? "resource_group" :
      "resource"
    )
  }

  assignments_mg       = { for k, a in local.assignments_all : k => a if local.assignment_scope_type[k] == "management_group" }
  assignments_rg       = { for k, a in local.assignments_all : k => a if local.assignment_scope_type[k] == "resource_group" }
  assignments_resource = { for k, a in local.assignments_all : k => a if local.assignment_scope_type[k] == "resource" }
  # Null scopes and unrecognized explicit types route here so this resource's preconditions can fail
  # the plan with a real message instead of the entry being silently dropped.
  assignments_sub = { for k, a in local.assignments_all : k => a if !contains(["management_group", "resource_group", "resource"], local.assignment_scope_type[k]) }

  # Azure caps assignment names at 24 characters at management group scope and 64 elsewhere; longer
  # derived names fall back to a stable hash (the display name stays readable).
  assignment_name = {
    for k, a in local.assignments_all : k => (
      a.name_override != null ? a.name_override : (
        local.assignment_scope_type[k] == "management_group"
        ? (length(a.bare_key) > 24 ? substr(sha1(a.bare_key), 0, 24) : a.bare_key)
        : substr(a.bare_key, 0, 64)
      )
    )
  }

  # ---------- Managed identity role grants ----------
  # One azurerm_role_assignment per (identity-bearing assignment, required role), granted at the
  # assignment scope so Modify / DeployIfNotExists remediation can act there. Keys are plan-known
  # (map key + role GUID); the computed principal id is looked up in the resource body.
  identity_role_grants = {
    for item in flatten([
      for k, a in local.assignments_all : [
        for rid in a.identity_role_definition_ids : {
          key            = "${k}|${rid}"
          assignment_key = k
          scope          = a.scope
          role_id        = "/providers/Microsoft.Authorization/roleDefinitions/${rid}"
        }
      ] if a.identity != null
    ]) : item.key => { assignment_key = item.assignment_key, scope = item.scope, role_id = item.role_id }
  }

  # ---------- Exemptions ----------
  # Internal reference resolution: an exemption points at a literal assignment id, an engine
  # assignment key, or a baseline key. The referenced id itself is computed, so it is resolved in the
  # exemption resource body via the scope-type lookup below.
  exemptions_normalized = {
    for k, e in local.exemptions_cfg : k => {
      name       = e.name
      scope      = try(coalesce(e.scope_id, var.scope_id), null)
      scope_type = e.scope_type != null ? e.scope_type : (e.scope_id == null ? var.scope_type : null)

      policy_assignment_id = e.policy_assignment_id
      internal_key = (
        e.assignment_key != null ? "custom|${e.assignment_key}" :
        e.baseline_key != null ? "baseline|${e.baseline_key}" :
        null
      )

      exemption_category              = e.exemption_category
      display_name                    = e.display_name
      description                     = e.description
      expires_on                      = e.expires_on
      policy_definition_reference_ids = e.policy_definition_reference_ids
      metadata                        = e.metadata == null ? null : try(tostring(e.metadata), jsonencode(e.metadata))

      internal_key_ok = (
        length([for t in [e.policy_assignment_id, e.assignment_key, e.baseline_key] : t if t != null]) == 1 &&
        (e.assignment_key == null || contains(keys(var.policy_assignments), coalesce(e.assignment_key, "-"))) &&
        (e.baseline_key == null || contains(keys(var.baseline_policies), coalesce(e.baseline_key, "-")))
      )
    }
  }

  exemption_scope_type = {
    for k, e in local.exemptions_normalized : k => (
      e.scope_type != null ? e.scope_type :
      e.scope == null ? "none" :
      startswith(lower(e.scope), "/providers/microsoft.management/managementgroups/") ? "management_group" :
      length(regexall("^/subscriptions/[^/]+$", lower(e.scope))) > 0 ? "subscription" :
      length(regexall("^/subscriptions/[^/]+/resourcegroups/[^/]+$", lower(e.scope))) > 0 ? "resource_group" :
      "resource"
    )
  }

  exemptions_mg       = { for k, e in local.exemptions_normalized : k => e if local.exemption_scope_type[k] == "management_group" }
  exemptions_rg       = { for k, e in local.exemptions_normalized : k => e if local.exemption_scope_type[k] == "resource_group" }
  exemptions_resource = { for k, e in local.exemptions_normalized : k => e if local.exemption_scope_type[k] == "resource" }
  exemptions_sub      = { for k, e in local.exemptions_normalized : k => e if !contains(["management_group", "resource_group", "resource"], local.exemption_scope_type[k]) }
}
