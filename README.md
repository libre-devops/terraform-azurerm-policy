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
- **NSP guardrails** (`nsp_guardrails`): ready-made custom policies for network security perimeters,
  where no built-ins exist. One opt-in flags NSP associations not in Enforced access mode, and (given
  `approved_perimeter_ids`) audits storage accounts and key vaults that are not associated with one of
  YOUR approved perimeters. The rules ship as versioned JSON under [`policies/`](./policies) and run
  through the module's own engine.

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
  messages, overrides, and resource selectors, exemptions targeting baseline and engine assignments,
  and the NSP guardrails pinned to a real network security perimeter. Everything is scoped to a disposable resource group, so the Deny effects govern nothing
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_management_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_exemption.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_exemption) | resource |
| [azurerm_management_group_policy_set_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_set_definition) | resource |
| [azurerm_policy_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_policy_set_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_set_definition) | resource |
| [azurerm_resource_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_resource_group_policy_exemption.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_exemption) | resource |
| [azurerm_resource_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_assignment) | resource |
| [azurerm_resource_policy_exemption.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_exemption) | resource |
| [azurerm_role_assignment.policy_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subscription_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
| [azurerm_subscription_policy_exemption.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_exemption) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_baseline_display_name_prefix"></a> [baseline\_display\_name\_prefix](#input\_baseline\_display\_name\_prefix) | Prefix prepended to baseline assignment display names so they are recognisable in the portal. | `string` | `"[LDO Baseline]"` | no |
| <a name="input_baseline_non_compliance_message"></a> [baseline\_non\_compliance\_message](#input\_baseline\_non\_compliance\_message) | Default non-compliance message for baseline assignments. The literal token {policy} is replaced with the policy display name. | `string` | `"Denied or flagged by the {policy} policy assignment. Contact the platform team if you believe this is in error."` | no |
| <a name="input_baseline_policies"></a> [baseline\_policies](#input\_baseline\_policies) | The curated baseline: which catalog policies to assign, keyed by catalog key (see catalog.tf; the<br/>baseline\_catalog\_keys output lists every key). An empty object {} accepts the entry's curated<br/>defaults. Optional attributes per entry:<br/><br/>- effect (string): override the curated default effect (validated against the definition's allowed<br/>  effects; entries with a fixed effect accept no override).<br/>- parameters (object of plain values): definition parameters, merged over the catalog defaults.<br/>  Entries with required parameters (allowed\_locations, allowed\_vm\_skus, the tag policies, ...) must<br/>  set them here.<br/>- enforce (bool): override enforcement mode (the require-tag pair default to false, an audit-style<br/>  rollout for their fixed Deny effect).<br/>- scope\_id / scope\_type (string): assign at a different scope than the module default; set scope\_type<br/>  when that scope id is a computed value.<br/>- non\_compliance\_message (string): override the templated default message.<br/>- not\_scopes (list(string)): child scopes excluded from the assignment.<br/>- display\_name / description (string): override the derived text. | `any` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region stamped on identity-bearing assignments (Modify / DeployIfNotExists policies require a located managed identity). Required when any baseline or engine assignment carries an identity. | `string` | `null` | no |
| <a name="input_nsp_guardrails"></a> [nsp\_guardrails](#input\_nsp\_guardrails) | Opt-in network security perimeter guardrails; null (the default) creates nothing. Set to an object<br/>(empty {} is valid) to enable:<br/><br/>- Always: "nsp-association-access-mode", a custom policy flagging NSP resource associations whose<br/>  access mode is not Enforced (Learning observes but does not block). Audit by default because<br/>  Learning is the sanctioned onboarding step; set access\_mode\_effect = "Deny" to hard-require<br/>  Enforced.<br/>- When approved\_perimeter\_ids is non-empty: "nsp-storage-perimeter-membership" and<br/>  "nsp-keyvault-perimeter-membership", AuditIfNotExists policies flagging storage accounts / key<br/>  vaults not associated with one of the approved perimeters. Narrow with require\_association\_for<br/>  (list of "storage\_account" / "key\_vault", default both).<br/><br/>Optional attributes: access\_mode\_effect (Audit \| Deny \| Disabled, default Audit),<br/>approved\_perimeter\_ids (list of perimeter resource ids), require\_association\_for,<br/>definition\_name\_suffix (appended to the definition names, since custom definitions are unique per<br/>subscription; set it when several module calls in one subscription enable these guardrails).<br/>Definitions are created at subscription scope; assignments land at the module scope\_id/scope\_type. | `any` | `null` | no |
| <a name="input_policy_assignments"></a> [policy\_assignments](#input\_policy\_assignments) | Policy assignments, keyed by assignment name. The target is exactly one of policy\_definition\_id (a<br/>full definition or initiative id, built-in or external), definition\_key, or set\_definition\_key (keys<br/>of this module call's custom definitions/sets, resolved for you). The scope type (management group,<br/>subscription, resource group, or resource) is detected from the effective scope\_id and routed to the<br/>matching azurerm resource; set scope\_type explicitly when the scope id is a computed value. Optional<br/>attributes per entry:<br/><br/>- scope\_id / scope\_type (string): defaults to the module scope.<br/>- parameters: plain values wrapped into the ARM assignment format for you, or a pre-rendered JSON<br/>  string passed through as-is.<br/>- display\_name, description, metadata, enforce (bool, default true), not\_scopes (list), location,<br/>  name (overrides the map key).<br/>- non\_compliance\_messages (list of { content, policy\_definition\_reference\_id }).<br/>- identity ({ type = SystemAssigned \| UserAssigned, identity\_ids }) with location for Modify /<br/>  DeployIfNotExists policies; identity\_role\_definition\_ids (list of role definition GUIDs, from the<br/>  policy definition's roleDefinitionIds) grants the identity those roles at the assignment scope.<br/>- overrides (list of { value, selectors = [{ in, not\_in }] }) and resource\_selectors (list of<br/>  { name, selectors = [{ kind, in, not\_in }] }). | `any` | `{}` | no |
| <a name="input_policy_definitions"></a> [policy\_definitions](#input\_policy\_definitions) | Custom policy definitions, keyed by definition name. Attributes per entry:<br/><br/>- display\_name (string, required).<br/>- policy\_rule (required): the rule as an HCL object (encoded for you) or a pre-rendered JSON string,<br/>  so a rule can live inline or in a versioned .json file loaded with file().<br/>- mode (string): All (default), Indexed, or a resource-provider data-plane mode.<br/>- parameters / metadata: HCL object or JSON string.<br/>- description (string), name (string, overrides the map key), management\_group\_id (string, defines at<br/>  a management group instead of the subscription). | `any` | `{}` | no |
| <a name="input_policy_exemptions"></a> [policy\_exemptions](#input\_policy\_exemptions) | Policy exemptions, keyed by exemption name. The exempted assignment is exactly one of<br/>policy\_assignment\_id (a full id), assignment\_key (a key of policy\_assignments), or baseline\_key (a key<br/>of baseline\_policies). scope\_id defaults to the module scope; the scope type is detected and routed to<br/>the matching azurerm resource (set scope\_type when the scope id is computed). Optional attributes per<br/>entry:<br/><br/>- exemption\_category (Waiver or Mitigated, default Waiver), expires\_on (RFC3339; Waivers warn without<br/>  one), display\_name, description, metadata, name (overrides the map key).<br/>- policy\_definition\_reference\_ids (list): exempt only specific members of an initiative. | `any` | `{}` | no |
| <a name="input_policy_set_definitions"></a> [policy\_set\_definitions](#input\_policy\_set\_definitions) | Custom initiatives (policy set definitions), keyed by set name. Attributes per entry:<br/><br/>- display\_name (string, required).<br/>- policy\_definition\_references (list, required): each reference sets exactly one of<br/>  policy\_definition\_id (full id, built-in or external) or definition\_key (a key of policy\_definitions<br/>  in this module call, resolved for you), plus optional parameter\_values (HCL object or JSON string),<br/>  reference\_id, and policy\_group\_names.<br/>- policy\_definition\_groups (list): name (required), display\_name, category, description,<br/>  additional\_metadata\_resource\_id.<br/>- parameters / metadata: HCL object or JSON string.<br/>- description (string), name (string, overrides the map key), management\_group\_id (string). | `any` | `{}` | no |
| <a name="input_scope_id"></a> [scope\_id](#input\_scope\_id) | The default scope assignments and exemptions attach to when an entry does not set its own scope\_id: a<br/>management group id (/providers/Microsoft.Management/managementGroups/<name>), a subscription id<br/>(/subscriptions/<guid>), a resource group id, or a single resource id. Required when baseline\_policies<br/>is used; optional when every engine entry carries its own scope. | `string` | `null` | no |
| <a name="input_scope_type"></a> [scope\_type](#input\_scope\_type) | Explicit scope type for scope\_id: management\_group, subscription, resource\_group, or resource. Usually<br/>unnecessary (the type is detected from the scope string), but REQUIRED when scope\_id is a computed<br/>value (for example a resource group id from a resource created in the same plan), because Terraform<br/>cannot inspect an unknown string to route the assignment. Entries can override with their own<br/>scope\_type alongside their own scope\_id. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_baseline_assignment_ids"></a> [baseline\_assignment\_ids](#output\_baseline\_assignment\_ids) | Map of baseline catalog key to assignment id (the baseline slice of policy\_assignment\_ids, bare keys). |
| <a name="output_baseline_catalog_keys"></a> [baseline\_catalog\_keys](#output\_baseline\_catalog\_keys) | Every key the curated baseline catalog offers, so callers can discover what baseline\_policies accepts. |
| <a name="output_identity_role_assignment_ids"></a> [identity\_role\_assignment\_ids](#output\_identity\_role\_assignment\_ids) | Map of "<assignment key>\|<role guid>" to the role assignment id granted to that policy assignment's managed identity. |
| <a name="output_policy_assignment_ids"></a> [policy\_assignment\_ids](#output\_policy\_assignment\_ids) | Map of internal assignment key ("baseline\|<key>" / "custom\|<key>") to assignment id. |
| <a name="output_policy_assignment_ids_zipmap"></a> [policy\_assignment\_ids\_zipmap](#output\_policy\_assignment\_ids\_zipmap) | Map of internal assignment key to { name, id }, for easy composition with other modules. |
| <a name="output_policy_assignments"></a> [policy\_assignments](#output\_policy\_assignments) | All assignments across the four scope types, keyed "baseline\|<key>" or "custom\|<key>": id, name, scope, scope type, display name, enforcement, and identity principal (null when the assignment has no identity). |
| <a name="output_policy_definition_ids"></a> [policy\_definition\_ids](#output\_policy\_definition\_ids) | Map of custom definition key to definition id. |
| <a name="output_policy_definitions"></a> [policy\_definitions](#output\_policy\_definitions) | The custom policy definitions, keyed by input key. Full resource objects. |
| <a name="output_policy_exemptions"></a> [policy\_exemptions](#output\_policy\_exemptions) | All exemptions across the four scope types, keyed by input key: id, name, category, and the exempted assignment id. |
| <a name="output_policy_set_definition_ids"></a> [policy\_set\_definition\_ids](#output\_policy\_set\_definition\_ids) | Map of custom initiative key to set definition id. |
| <a name="output_policy_set_definitions"></a> [policy\_set\_definitions](#output\_policy\_set\_definitions) | The custom initiatives (subscription and management-group scoped), keyed by input key. Curated projection (a full-object output would touch the classic resource's deprecated management\_group\_id attribute). |
<!-- END_TF_DOCS -->
