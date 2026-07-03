output "baseline_assignment_ids" {
  description = "Map of baseline catalog key to assignment id."
  value       = module.policy.baseline_assignment_ids
}

output "policy_assignment_ids" {
  description = "Map of internal assignment key to assignment id."
  value       = module.policy.policy_assignment_ids
}
