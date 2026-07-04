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

## The deploy story, in full

Deploying code to flex consumption is unlike every other Functions plan, and each of these
statements was verified live while building this module:

**How flex deployment actually works.** The app runs from a package in its deployment storage
container, but the container is not a drop-box: the host loads the one package the deployment
service produced. A deploy means the deployment service takes your zip, runs the remote build
(Python dependencies are installed server-side; your zip carries source only), writes the BUILT
artifact into the deployment container under its own layout, and flips the host metadata so
instances load it. Uploading a blob yourself does nothing. There is no Kudu console, no site
extensions, and no WEBSITE_RUN_FROM_PACKAGE on flex; only a minimal deployment endpoint.

**The paths, and what is wrong with each:**

| Path | Verdict | Why |
| --- | --- | --- |
| `zip_deploy_file` (provider attribute) | Broken upstream | After pushing, the provider polls a deployment-status endpoint that 404s on flex apps even when healthy; reproduced with clean identity setup, and AVM built their own one-deploy submodule rather than use it. Passthrough kept for when it is fixed; a check steers you away. |
| `az functionapp deployment source config-zip` (push bytes) | Works with fresh credentials only | This is the classic "create an empty app, then CLI build-and-deploy" flow, and it is fine interactively. Inside a Terraform apply on CI it dies: the runner's OIDC assertion expires five minutes after login (AADSTS700024), long before a flex stack finishes applying, and Terraform cannot POST binary bodies itself. |
| ARM one-deploy with `packageUri` (pull; what the complete example does) | Works, with one asterisk | The download is anonymous: no identity option exists on that API, so the URL must be a SAS, and SAS needs account keys. The example therefore stages the package in a tiny keys-on TRANSPORT account and hands one-deploy a short-lived read-only SAS. The app's own storage stays fully keyless: the deployment service writes the built package into it server-side under the app's identity. (AVM's equivalent uses a one-year SAS and keeps keys on the app's storage; quarantining the SAS to a transport account is strictly tighter.) |
| Dropping the zip in the deployment container with `azurerm_storage_blob` | Does nothing | No build, no metadata flip; the host never looks at it. |
| Locking the storage to the app's outbound IPs | Breaks everything | Deploys 403 and the running host 503s: flex reaches its storage from platform ranges, not the published outbound IPs. VNet integration with service or private endpoints is the only working lockdown. |
| Vendored packages (build on the runner, deploy with remote build off) | Works, and mandatory for egress-blocked apps | Build where the internet is: `pip install --target .python_packages/lib/site-packages -r requirements.txt` on the runner, zip the result, deploy with `remoteBuild: false`. The deployment service then does no pip at all, which is required when the app cannot reach PyPI (VNet-isolated), and the artifact you tested is byte-identical to what runs. Wheel tags must match the target (linux x86_64, the app's Python minor). |

**So is it keyless?** The app and its storage, yes, end to end, and a FULLY keyless deploy is
possible whenever the pusher holds a live AAD token: push-bytes (config-zip or the GitHub
functions-action) against a keyless app works with no keys and no SAS anywhere, verified live.
What is not possible today is fully keyless from INSIDE a single Terraform apply: Terraform
cannot POST binary bodies, CLI tokens expire mid-apply, and the pull path fetches anonymously,
hence the SAS on a throwaway transport account. It cannot be otherwise until Microsoft either
fixes the provider's push path or teaches one-deploy to fetch with an identity; the day either
lands, the transport account disappears and nothing else changes.

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
