<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Policy

A KISS Azure Policy module: a curated baseline of sensible built-in policies to get you governing
quickly, plus a simple engine for your own definitions, initiatives, assignments, and exemptions at
any scope.

[![CI](https://github.com/libre-devops/terraform-azurerm-policy/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-policy/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-policy?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-policy/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-policy)](./LICENSE)

---

## Overview

This is deliberately NOT an enterprise landing-zone framework clone. It is the pragmatic middle
ground: far better scale and consistency than clicking policies together manually, without the
ceremony of a full ALZ policy estate. Two layers in one module:

- **The curated baseline** (`baseline_policies`): a catalog of sensible BUILT-IN Microsoft policies,
  assigned individually so each is toggled, tuned, and exempted on its own. Adding a policy is one map
  entry; Microsoft maintains the definitions. Hard technical guardrails default to **Deny** (storage
  public access, secure transfer, TLS floors, key vault soft delete, vault firewall, NIC public IPs,
  App Service HTTPS, SQL TLS); behavioural or noisy policies default to **Audit**; the fixed-Deny
  require-tag pair roll out in **DoNotEnforce** until you escalate them. Every entry's GUID, parameter
  names, allowed effects, and role requirements were verified against the live platform, and every
  default is overridable per entry. The `baseline_catalog_keys` output lists the catalog.
- **The engine** (`policy_definitions`, `policy_set_definitions`, `policy_assignments`,
  `policy_exemptions`): your own policies, cleanly. A custom policy is one versioned .json rule file
  (hand-written or exported from the portal) plus one map entry, or an inline HCL object; assignments
  and initiatives reference it by key and the module resolves the ids. Assignments target anything
  (custom or built-in) at **any scope** (management group, subscription, resource group, or single
  resource, detected from the scope id and routed to the right resource), and exemptions target an
  assignment by key.

Enterprise conveniences handled for you: plain parameter values are wrapped into the ARM assignment
format; Modify / DeployIfNotExists assignments get a system-assigned identity and the module grants it
the roles the definition requires at the assignment scope; non-compliance messages are templated;
management-group assignment names longer than Azure's 24-character cap fall back to a stable hash; and
misconfiguration (unknown catalog key, missing required parameters, invalid effect, missing scope)
fails the plan with a specific message.

One rule to remember: when a scope id is **computed** (a resource group created in the same plan, for
example), set `scope_type` explicitly, because Terraform cannot inspect an unknown string to route the
assignment.

## Usage

```hcl
module "policy" {
  source  = "libre-devops/policy/azurerm"
  version = "~> 4.0"

  scope_id = "/subscriptions/00000000-0000-0000-0000-000000000000"

  baseline_policies = {
    # Required-parameter entries.
    allowed_locations = {
      parameters = { listOfAllowedLocations = ["uksouth", "ukwest"] }
    }

    # Curated defaults: hard guardrails arrive as Deny.
    storage_deny_public_access = {}
    storage_secure_transfer    = {}
    keyvault_soft_delete       = {}

    # Fixed-Deny tag policy: starts in DoNotEnforce, escalate when ready.
    require_tag_on_resources = {
      parameters = { tagName = "CostCentre" }
      enforce    = true
    }

    # Broad audit coverage via the MCSB initiative.
    mcsb = {}
  }

  # The engine: anything custom.
  policy_definitions = {
    approved-providers = {
      display_name = "Approved resource providers"
      mode         = "Indexed"
      policy_rule  = file("${path.module}/policies/approved-providers.json")
    }
  }

  policy_assignments = {
    approved-providers = {
      definition_key = "approved-providers"
      parameters     = { approvedProviders = ["Microsoft.Storage", "Microsoft.Network"] }
    }
  }

  policy_exemptions = {
    legacy-rg = {
      baseline_key       = "storage_deny_public_access"
      scope_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy"
      exemption_category = "Waiver"
      expires_on         = "2027-01-01T00:00:00Z"
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - three guardrails at resource group scope, including a
  one-line override of a curated default (soft delete softened to Audit) and the computed-scope
  `scope_type` pattern.
- [`examples/complete`](./examples/complete) - the full surface: the baseline with parameters, effect
  and enforcement overrides, the identity-bearing Modify policy with its automatic role grant, the
  MCSB initiative, custom definitions (one from a versioned .json file, one inline HCL), a custom
  initiative, engine assignments with non-compliance
  messages, overrides, and resource selectors, and exemptions targeting baseline and engine
  assignments. Everything is scoped to a disposable resource group, so the Deny effects govern nothing
  but the example itself.

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in [`.trivyignore.yaml`](./.trivyignore.yaml) (the
machine-applied source of truth, passed to Trivy with `--ignorefile`) and are mirrored in a table
here so the reason is auditable.

There are currently **no exceptions**: the module and its examples scan clean. The module's whole
purpose is to raise the security posture of a scope, so there is nothing to waive.

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here recording the reason. Both the file and
the table are reviewed in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.
