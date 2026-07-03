output "baseline_assignment_ids" {
  description = "Map of baseline catalog key to assignment id."
  value       = module.policy.baseline_assignment_ids
}

output "baseline_catalog_keys" {
  description = "Every key the curated baseline catalog offers."
  value       = module.policy.baseline_catalog_keys
}

output "identity_role_assignment_ids" {
  description = "Role assignments granted to policy-assignment managed identities."
  value       = module.policy.identity_role_assignment_ids
}

output "policy_assignments" {
  description = "All assignments with id, scope, enforcement, and identity principal."
  value       = module.policy.policy_assignments
}

output "policy_definition_ids" {
  description = "Map of custom definition key to definition id."
  value       = module.policy.policy_definition_ids
}

output "policy_exemptions" {
  description = "All exemptions with id, category, and the exempted assignment."
  value       = module.policy.policy_exemptions
}

output "policy_set_definition_ids" {
  description = "Map of custom initiative key to set definition id."
  value       = module.policy.policy_set_definition_ids
}
