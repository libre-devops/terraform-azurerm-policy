# Tests for the module. The azurerm provider is mocked, so no credentials and no cloud calls:
#   terraform init -backend=false && terraform test
# command = apply is used where computed ids (definition ids, assignment ids) must be resolvable.

# Mocked computed ids must LOOK like real ARM ids: the provider parses referenced ids (a set
# definition validates its member definition ids, an exemption parses its assignment id), so the
# default random-string mocks would fail that parsing.
mock_provider "azurerm" {
  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/mock-definition"
    }
  }
  mock_resource "azurerm_policy_set_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock-set"
    }
  }
  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/mock-mg/providers/Microsoft.Authorization/policySetDefinitions/mock-set"
    }
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
    }
  }
  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
    }
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/mock-mg/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
    }
  }
}

variables {
  scope_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
}

# Baseline defaults: hard guardrails carry Deny, curated parameters flow, and the require-tag pair
# roll out in DoNotEnforce (which the visibility check deliberately flags).
run "baseline_defaults" {
  command = apply

  variables {
    baseline_policies = {
      storage_deny_public_access = {}
      storage_minimum_tls        = {}
      require_tag_on_resources   = { parameters = { tagName = "CostCentre" } }
    }
  }

  expect_failures = [check.unenforced_assignments_are_visible]

  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 3
    error_message = "All three baseline entries should land as subscription assignments."
  }

  assert {
    condition     = jsondecode(azurerm_subscription_policy_assignment.this["baseline|storage_deny_public_access"].parameters).effect.value == "Deny"
    error_message = "storage_deny_public_access should default to Deny."
  }

  assert {
    condition     = jsondecode(azurerm_subscription_policy_assignment.this["baseline|storage_minimum_tls"].parameters).minimumTlsVersion.value == "TLS1_2"
    error_message = "storage_minimum_tls should carry the curated TLS1_2 default parameter."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["baseline|require_tag_on_resources"].enforce == false
    error_message = "require_tag_on_resources should default to DoNotEnforce (audit-style rollout of a fixed-Deny policy)."
  }

  assert {
    condition     = startswith(azurerm_subscription_policy_assignment.this["baseline|storage_deny_public_access"].display_name, "[LDO Baseline]")
    error_message = "Baseline display names should carry the baseline prefix."
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.this["baseline|storage_minimum_tls"].non_compliance_message) == 1
    error_message = "Baseline assignments should carry the templated non-compliance message."
  }
}

# Effect and enforce overrides flow through.
run "baseline_overrides" {
  command = apply

  variables {
    baseline_policies = {
      storage_secure_transfer  = { effect = "Audit" }
      require_tag_on_resources = { parameters = { tagName = "Owner" }, enforce = true }
    }
  }

  assert {
    condition     = jsondecode(azurerm_subscription_policy_assignment.this["baseline|storage_secure_transfer"].parameters).effect.value == "Audit"
    error_message = "An effect override should replace the curated default."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["baseline|require_tag_on_resources"].enforce == true
    error_message = "An enforce override should escalate the require-tag policy to enforced."
  }
}

# Scope routing: the scope string decides the assignment resource, and management group names longer
# than 24 characters fall back to a stable hash.
run "scope_routing" {
  command = apply

  variables {
    baseline_policies = {
      storage_deny_public_access = { scope_id = "/providers/Microsoft.Management/managementGroups/mg-platform" }
      keyvault_soft_delete       = { scope_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001" }
      storage_secure_transfer    = {}
    }
  }

  assert {
    condition     = length(azurerm_management_group_policy_assignment.this) == 1 && length(azurerm_resource_group_policy_assignment.this) == 1 && length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Entries should route to the management group, resource group, and subscription resources by scope."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.this["baseline|storage_deny_public_access"].name == substr(sha1("storage_deny_public_access"), 0, 24)
    error_message = "A management-group assignment name longer than 24 characters should fall back to the stable hash."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["baseline|keyvault_soft_delete"].name == "keyvault_soft_delete"
    error_message = "Resource-group assignment names should keep the bare catalog key."
  }
}

# An unknown catalog key fails the plan via the resource precondition.
run "rejects_unknown_catalog_key" {
  command = plan

  variables {
    baseline_policies = {
      not_a_real_policy = {}
    }
  }

  expect_failures = [azurerm_subscription_policy_assignment.this]
}

# Missing required parameters fail the plan via the resource precondition.
run "rejects_missing_required_parameters" {
  command = plan

  variables {
    baseline_policies = {
      allowed_locations = {}
    }
  }

  expect_failures = [azurerm_subscription_policy_assignment.this]
}

# An effect the definition does not accept fails the plan (fixed-effect entries accept no override).
run "rejects_invalid_effect" {
  command = plan

  variables {
    baseline_policies = {
      allowed_vm_skus = { effect = "Deny", parameters = { listOfAllowedSKUs = ["Standard_B2s"] } }
    }
  }

  expect_failures = [azurerm_subscription_policy_assignment.this]
}

# The engine chain: a custom definition, an initiative referencing it by key alongside a built-in, an
# assignment of that initiative, and an exemption pointing back at an engine assignment key.
run "custom_definition_initiative_assignment_exemption" {
  command = apply

  variables {
    policy_definitions = {
      approved-providers = {
        display_name = "Approved resource providers"
        mode         = "Indexed"
        policy_rule = {
          if = {
            not = {
              value = "[first(split(field('type'), '/'))]"
              in    = "[parameters('approvedProviders')]"
            }
          }
          then = { effect = "[parameters('effect')]" }
        }
        parameters = {
          approvedProviders = { type = "Array" }
          effect = {
            type          = "String"
            allowedValues = ["Audit", "Deny", "Disabled"]
            defaultValue  = "Audit"
          }
        }
      }
    }

    policy_set_definitions = {
      governance-baseline = {
        display_name = "Governance baseline"
        policy_definition_references = [
          { definition_key = "approved-providers", parameter_values = { approvedProviders = { value = ["Microsoft.Storage"] } } },
          { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/a451c1ef-c6ca-483d-87ed-f49761e3ffb5" },
        ]
      }
    }

    policy_assignments = {
      governance = {
        set_definition_key = "governance-baseline"
        display_name       = "Governance baseline"
      }
    }

    policy_exemptions = {
      break-glass = {
        assignment_key     = "governance"
        exemption_category = "Mitigated"
        description        = "Compensating control documented in the risk register."
      }
    }
  }

  assert {
    condition     = azurerm_policy_definition.this["approved-providers"].policy_type == "Custom"
    error_message = "The custom definition should be created as Custom."
  }

  assert {
    condition     = length(azurerm_policy_set_definition.this["governance-baseline"].policy_definition_reference) == 2
    error_message = "The initiative should reference the custom definition and the built-in."
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1 && length(azurerm_subscription_policy_exemption.this) == 1
    error_message = "The initiative assignment and the exemption should be created at subscription scope."
  }
}

# An exemption can target a baseline entry by key, and it lands at the exemption's own scope.
run "exemption_targets_baseline_key" {
  command = apply

  variables {
    baseline_policies = {
      storage_deny_public_access = {}
    }
    policy_exemptions = {
      legacy-rg = {
        baseline_key       = "storage_deny_public_access"
        scope_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy"
        exemption_category = "Waiver"
        expires_on         = "2027-01-01T00:00:00Z"
        description        = "Legacy static websites; remediation tracked."
      }
    }
  }

  assert {
    condition     = length(azurerm_resource_group_policy_exemption.this) == 1
    error_message = "The exemption should land on the resource-group exemption resource."
  }
}

# Identity-bearing baseline entry: the Modify policy gets a system-assigned identity and the module
# grants the definition's required role at the assignment scope.
run "identity_and_role_grant" {
  command = apply

  variables {
    location = "uksouth"
    baseline_policies = {
      inherit_tag_from_rg = { parameters = { tagName = "CostCentre" } }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["baseline|inherit_tag_from_rg"].identity[0].type == "SystemAssigned"
    error_message = "The Modify policy assignment should carry a system-assigned identity."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["baseline|inherit_tag_from_rg"].location == "uksouth"
    error_message = "The identity-bearing assignment should be stamped with the module location."
  }

  assert {
    condition     = azurerm_role_assignment.policy_identity["baseline|inherit_tag_from_rg|b24988ac-6180-42a0-ab88-20f7382dd24c"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
    error_message = "The identity should be granted the Contributor role the definition's roleDefinitionIds require."
  }
}

# Identity without a location fails the plan via the precondition.
run "rejects_identity_without_location" {
  command = plan

  variables {
    baseline_policies = {
      inherit_tag_from_rg = { parameters = { tagName = "CostCentre" } }
    }
  }

  expect_failures = [azurerm_subscription_policy_assignment.this]
}
