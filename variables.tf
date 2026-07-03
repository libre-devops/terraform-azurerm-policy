variable "baseline_display_name_prefix" {
  description = "Prefix prepended to baseline assignment display names so they are recognisable in the portal."
  type        = string
  default     = "[LDO Baseline]"
}

variable "baseline_non_compliance_message" {
  description = "Default non-compliance message for baseline assignments. The literal token {policy} is replaced with the policy display name."
  type        = string
  default     = "Denied or flagged by the {policy} policy assignment. Contact the platform team if you believe this is in error."
}

variable "baseline_policies" {
  description = <<DESC
The curated baseline: which catalog policies to assign, keyed by catalog key (see catalog.tf; the
baseline_catalog_keys output lists every key). An empty object {} accepts the entry's curated
defaults. Optional attributes per entry:

- effect (string): override the curated default effect (validated against the definition's allowed
  effects; entries with a fixed effect accept no override).
- parameters (object of plain values): definition parameters, merged over the catalog defaults.
  Entries with required parameters (allowed_locations, allowed_vm_skus, the tag policies, ...) must
  set them here.
- enforce (bool): override enforcement mode (the require-tag pair default to false, an audit-style
  rollout for their fixed Deny effect).
- scope_id / scope_type (string): assign at a different scope than the module default; set scope_type
  when that scope id is a computed value.
- non_compliance_message (string): override the templated default message.
- not_scopes (list(string)): child scopes excluded from the assignment.
- display_name / description (string): override the derived text.
DESC

  type    = any
  default = {}

  validation {
    condition     = can({ for k, v in var.baseline_policies : k => v })
    error_message = "baseline_policies must be a map of objects keyed by catalog key."
  }
}

variable "location" {
  description = "Azure region stamped on identity-bearing assignments (Modify / DeployIfNotExists policies require a located managed identity). Required when any baseline or engine assignment carries an identity."
  type        = string
  default     = null
}

variable "policy_assignments" {
  description = <<DESC
Policy assignments, keyed by assignment name. The target is exactly one of policy_definition_id (a
full definition or initiative id, built-in or external), definition_key, or set_definition_key (keys
of this module call's custom definitions/sets, resolved for you). The scope type (management group,
subscription, resource group, or resource) is detected from the effective scope_id and routed to the
matching azurerm resource; set scope_type explicitly when the scope id is a computed value. Optional
attributes per entry:

- scope_id / scope_type (string): defaults to the module scope.
- parameters: plain values wrapped into the ARM assignment format for you, or a pre-rendered JSON
  string passed through as-is.
- display_name, description, metadata, enforce (bool, default true), not_scopes (list), location,
  name (overrides the map key).
- non_compliance_messages (list of { content, policy_definition_reference_id }).
- identity ({ type = SystemAssigned | UserAssigned, identity_ids }) with location for Modify /
  DeployIfNotExists policies; identity_role_definition_ids (list of role definition GUIDs, from the
  policy definition's roleDefinitionIds) grants the identity those roles at the assignment scope.
- overrides (list of { value, selectors = [{ in, not_in }] }) and resource_selectors (list of
  { name, selectors = [{ kind, in, not_in }] }).
DESC

  type    = any
  default = {}

  validation {
    condition     = can({ for k, v in var.policy_assignments : k => v })
    error_message = "policy_assignments must be a map of objects keyed by assignment name."
  }
}

variable "policy_definitions" {
  description = <<DESC
Custom policy definitions, keyed by definition name. Attributes per entry:

- display_name (string, required).
- policy_rule (required): the rule as an HCL object (encoded for you) or a pre-rendered JSON string,
  so a rule can live inline or in a versioned .json file loaded with file().
- mode (string): All (default), Indexed, or a resource-provider data-plane mode.
- parameters / metadata: HCL object or JSON string.
- description (string), name (string, overrides the map key), management_group_id (string, defines at
  a management group instead of the subscription).
DESC

  type    = any
  default = {}

  validation {
    condition     = can({ for k, v in var.policy_definitions : k => v })
    error_message = "policy_definitions must be a map of objects keyed by definition name."
  }
}

variable "policy_exemptions" {
  description = <<DESC
Policy exemptions, keyed by exemption name. The exempted assignment is exactly one of
policy_assignment_id (a full id), assignment_key (a key of policy_assignments), or baseline_key (a key
of baseline_policies). scope_id defaults to the module scope; the scope type is detected and routed to
the matching azurerm resource (set scope_type when the scope id is computed). Optional attributes per
entry:

- exemption_category (Waiver or Mitigated, default Waiver), expires_on (RFC3339; Waivers warn without
  one), display_name, description, metadata, name (overrides the map key).
- policy_definition_reference_ids (list): exempt only specific members of an initiative.
DESC

  type    = any
  default = {}

  validation {
    condition     = can({ for k, v in var.policy_exemptions : k => v })
    error_message = "policy_exemptions must be a map of objects keyed by exemption name."
  }
}

variable "policy_set_definitions" {
  description = <<DESC
Custom initiatives (policy set definitions), keyed by set name. Attributes per entry:

- display_name (string, required).
- policy_definition_references (list, required): each reference sets exactly one of
  policy_definition_id (full id, built-in or external) or definition_key (a key of policy_definitions
  in this module call, resolved for you), plus optional parameter_values (HCL object or JSON string),
  reference_id, and policy_group_names.
- policy_definition_groups (list): name (required), display_name, category, description,
  additional_metadata_resource_id.
- parameters / metadata: HCL object or JSON string.
- description (string), name (string, overrides the map key), management_group_id (string).
DESC

  type    = any
  default = {}

  validation {
    condition     = can({ for k, v in var.policy_set_definitions : k => v })
    error_message = "policy_set_definitions must be a map of objects keyed by set name."
  }
}

variable "scope_id" {
  description = <<DESC
The default scope assignments and exemptions attach to when an entry does not set its own scope_id: a
management group id (/providers/Microsoft.Management/managementGroups/<name>), a subscription id
(/subscriptions/<guid>), a resource group id, or a single resource id. Required when baseline_policies
is used; optional when every engine entry carries its own scope.
DESC

  type    = string
  default = null
}

variable "scope_type" {
  description = <<DESC
Explicit scope type for scope_id: management_group, subscription, resource_group, or resource. Usually
unnecessary (the type is detected from the scope string), but REQUIRED when scope_id is a computed
value (for example a resource group id from a resource created in the same plan), because Terraform
cannot inspect an unknown string to route the assignment. Entries can override with their own
scope_type alongside their own scope_id.
DESC

  type    = string
  default = null

  validation {
    condition     = var.scope_type == null || contains(["management_group", "subscription", "resource_group", "resource"], coalesce(var.scope_type, "subscription"))
    error_message = "scope_type must be management_group, subscription, resource_group, or resource."
  }
}
