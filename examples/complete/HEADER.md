<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The full surface of the module, everything scoped to a disposable resource group so the Deny effects
govern nothing but the example itself. The baseline exercises required parameters (allowed locations,
VM SKUs), curated Deny defaults, an effect override, the fixed-Deny require-tag policy escalated to
enforced, the identity-bearing Modify policy (system-assigned identity plus its automatic Contributor
grant), and the MCSB initiative with a custom non-compliance message. The engine exercises a custom
definition (HCL policy rule), a custom initiative mixing that definition with a built-in, an
assignment with per-reference non-compliance messages, a built-in assignment with overrides and
resource selectors, and exemptions targeting a baseline entry (Mitigated) and an engine assignment
(time-boxed Waiver). Management-group scope is exercised in [`tests`](../../tests) with a mocked
provider, since the CI principal holds subscription Owner only. Run it with `just e2e complete`,
which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
