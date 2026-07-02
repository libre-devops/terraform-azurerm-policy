# check blocks run after every plan and apply and warn (without blocking) on configuration that would
# quietly do less than intended. Hard failures (bad catalog keys, missing required parameters, missing
# scope, identity without location) are resource preconditions in main.tf instead, so they stop the
# plan with a specific message.

# The module does nothing without at least one definition, initiative, assignment, exemption, or
# NSP guardrail.
check "creates_something" {
  assert {
    condition     = length(var.baseline_policies) + length(var.policy_definitions) + length(var.policy_set_definitions) + length(var.policy_assignments) + length(var.policy_exemptions) + length(local.nsp_definitions_cfg) > 0
    error_message = "No policy objects would be created: set baseline_policies, policy_definitions, policy_set_definitions, policy_assignments, policy_exemptions, or nsp_guardrails."
  }
}

# DoNotEnforce entries evaluate compliance but block nothing; surface them so an audit-style rollout
# (deliberate for the require-tag pair) is a visible state, not a forgotten one.
check "unenforced_assignments_are_visible" {
  assert {
    condition     = length([for k, a in local.assignments_all : k if !a.enforce]) == 0
    error_message = "These assignments run in DoNotEnforce mode (compliance is reported, nothing is blocked): ${join(", ", sort([for k, a in local.assignments_all : a.bare_key if !a.enforce]))}. Set enforce = true per entry when ready to enforce."
  }
}

# A Waiver exemption without an expiry tends to become permanent; nudge for a review date. Reads the
# normalized cfg (never the raw any-typed variable, whose entries may lack the attributes entirely).
check "waiver_exemptions_expire" {
  assert {
    condition     = alltrue([for e in values(local.exemptions_cfg) : !(e.exemption_category == "Waiver" && e.expires_on == null)])
    error_message = "These Waiver exemptions have no expires_on: ${join(", ", sort([for k, e in local.exemptions_cfg : k if e.exemption_category == "Waiver" && e.expires_on == null]))}. Waivers should carry a review date."
  }
}
