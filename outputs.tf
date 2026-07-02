output "policy_definitions" {
  description = "The custom policy definitions, keyed by input key. Full resource objects."
  value       = azurerm_policy_definition.this
}

output "policy_definition_ids" {
  description = "Map of custom definition key to definition id."
  value       = { for k, d in azurerm_policy_definition.this : k => d.id }
}

output "policy_set_definitions" {
  description = "The custom initiatives (subscription and management-group scoped), keyed by input key. Curated projection (a full-object output would touch the classic resource's deprecated management_group_id attribute)."
  value = merge(
    { for k, s in azurerm_policy_set_definition.this : k => { id = s.id, name = s.name, display_name = s.display_name, description = s.description, metadata = s.metadata, policy_definition_reference = s.policy_definition_reference } },
    { for k, s in azurerm_management_group_policy_set_definition.this : k => { id = s.id, name = s.name, display_name = s.display_name, description = s.description, metadata = s.metadata, policy_definition_reference = s.policy_definition_reference } },
  )
}

output "policy_set_definition_ids" {
  description = "Map of custom initiative key to set definition id."
  value = merge(
    { for k, s in azurerm_policy_set_definition.this : k => s.id },
    { for k, s in azurerm_management_group_policy_set_definition.this : k => s.id },
  )
}

output "policy_assignments" {
  description = "All assignments across the four scope types, keyed \"baseline|<key>\" or \"custom|<key>\": id, name, scope, scope type, display name, enforcement, and identity principal (null when the assignment has no identity)."
  value = merge(
    { for k, a in azurerm_management_group_policy_assignment.this : k => { id = a.id, name = a.name, scope = a.management_group_id, scope_type = "management_group", display_name = a.display_name, enforce = a.enforce, identity_principal_id = try(a.identity[0].principal_id, null) } },
    { for k, a in azurerm_subscription_policy_assignment.this : k => { id = a.id, name = a.name, scope = a.subscription_id, scope_type = "subscription", display_name = a.display_name, enforce = a.enforce, identity_principal_id = try(a.identity[0].principal_id, null) } },
    { for k, a in azurerm_resource_group_policy_assignment.this : k => { id = a.id, name = a.name, scope = a.resource_group_id, scope_type = "resource_group", display_name = a.display_name, enforce = a.enforce, identity_principal_id = try(a.identity[0].principal_id, null) } },
    { for k, a in azurerm_resource_policy_assignment.this : k => { id = a.id, name = a.name, scope = a.resource_id, scope_type = "resource", display_name = a.display_name, enforce = a.enforce, identity_principal_id = try(a.identity[0].principal_id, null) } },
  )
}

output "policy_assignment_ids" {
  description = "Map of internal assignment key (\"baseline|<key>\" / \"custom|<key>\") to assignment id."
  value = merge(
    { for k, a in azurerm_management_group_policy_assignment.this : k => a.id },
    { for k, a in azurerm_subscription_policy_assignment.this : k => a.id },
    { for k, a in azurerm_resource_group_policy_assignment.this : k => a.id },
    { for k, a in azurerm_resource_policy_assignment.this : k => a.id },
  )
}

output "policy_assignment_ids_zipmap" {
  description = "Map of internal assignment key to { name, id }, for easy composition with other modules."
  value = merge(
    { for k, a in azurerm_management_group_policy_assignment.this : k => { name = a.name, id = a.id } },
    { for k, a in azurerm_subscription_policy_assignment.this : k => { name = a.name, id = a.id } },
    { for k, a in azurerm_resource_group_policy_assignment.this : k => { name = a.name, id = a.id } },
    { for k, a in azurerm_resource_policy_assignment.this : k => { name = a.name, id = a.id } },
  )
}

output "baseline_assignment_ids" {
  description = "Map of baseline catalog key to assignment id (the baseline slice of policy_assignment_ids, bare keys)."
  value = {
    for k, id in merge(
      { for k, a in azurerm_management_group_policy_assignment.this : k => a.id },
      { for k, a in azurerm_subscription_policy_assignment.this : k => a.id },
      { for k, a in azurerm_resource_group_policy_assignment.this : k => a.id },
      { for k, a in azurerm_resource_policy_assignment.this : k => a.id },
    ) : trimprefix(k, "baseline|") => id if startswith(k, "baseline|")
  }
}

output "baseline_catalog_keys" {
  description = "Every key the curated baseline catalog offers, so callers can discover what baseline_policies accepts."
  value       = sort(keys(local.baseline_catalog))
}

output "policy_exemptions" {
  description = "All exemptions across the four scope types, keyed by input key: id, name, category, and the exempted assignment id."
  value = merge(
    { for k, e in azurerm_management_group_policy_exemption.this : k => { id = e.id, name = e.name, exemption_category = e.exemption_category, policy_assignment_id = e.policy_assignment_id } },
    { for k, e in azurerm_subscription_policy_exemption.this : k => { id = e.id, name = e.name, exemption_category = e.exemption_category, policy_assignment_id = e.policy_assignment_id } },
    { for k, e in azurerm_resource_group_policy_exemption.this : k => { id = e.id, name = e.name, exemption_category = e.exemption_category, policy_assignment_id = e.policy_assignment_id } },
    { for k, e in azurerm_resource_policy_exemption.this : k => { id = e.id, name = e.name, exemption_category = e.exemption_category, policy_assignment_id = e.policy_assignment_id } },
  )
}

output "identity_role_assignment_ids" {
  description = "Map of \"<assignment key>|<role guid>\" to the role assignment id granted to that policy assignment's managed identity."
  value       = { for k, r in azurerm_role_assignment.policy_identity : k => r.id }
}
