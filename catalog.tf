# The curated baseline catalog: sensible, enterprise-grade BUILT-IN policies, assigned individually.
# Microsoft maintains the definitions; this file only records which ones the baseline offers and how
# they are assigned by default. Every GUID, parameter name, allowed-effect list, and role requirement
# below was verified against the live platform (az policy definition show) on 2026-07-02; do not edit
# from memory, re-verify.
#
# Catalog entry shape:
#   policy_id            - full resource id of the built-in definition (or initiative when is_set).
#   is_set               - true when the entry is an initiative (policy set definition).
#   display_name         - the built-in's display name (assignment display name derives from it).
#   category             - the built-in's category, recorded for documentation.
#   description          - what the policy does and why the baseline includes it.
#   effect_parameter     - name of the definition's effect parameter, or null when the effect is fixed.
#   allowed_effects      - values the effect parameter accepts (empty when fixed).
#   default_effect       - the baseline's chosen default (hard guardrails Deny, noisy ones Audit).
#   default_parameters   - non-effect parameter defaults the baseline applies.
#   required_parameters  - parameter names the caller MUST supply for the entry to be valid.
#   default_enforce      - default enforcement mode (false = DoNotEnforce, an audit-style rollout for
#                          fixed-Deny policies such as the require-tag pair).
#   identity_role_definition_ids - role definition GUIDs a Modify/DeployIfNotExists assignment's
#                          managed identity needs; non-empty marks the entry as identity-bearing.
locals {
  baseline_catalog = {
    # ---------- General / governance ----------
    allowed_locations = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      is_set                       = false
      display_name                 = "Allowed locations"
      category                     = "General"
      description                  = "Restricts the regions resources can be deployed to. Configure listOfAllowedLocations."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = ["listOfAllowedLocations"]
      default_enforce              = true
      identity_role_definition_ids = []
    }
    allowed_locations_resource_groups = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
      is_set                       = false
      display_name                 = "Allowed locations for resource groups"
      category                     = "General"
      description                  = "Restricts the regions resource groups can be created in. Configure listOfAllowedLocations."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = ["listOfAllowedLocations"]
      default_enforce              = true
      identity_role_definition_ids = []
    }
    not_allowed_resource_types = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/6c112d4e-5bc7-47ae-a041-ea2d9dccd749"
      is_set                       = false
      display_name                 = "Not allowed resource types"
      category                     = "General"
      description                  = "Blocks a deny-list of resource types. Configure listOfResourceTypesNotAllowed."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = ["listOfResourceTypesNotAllowed"]
      default_enforce              = true
      identity_role_definition_ids = []
    }
    allowed_vm_skus = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
      is_set                       = false
      display_name                 = "Allowed virtual machine size SKUs"
      category                     = "Compute"
      description                  = "Restricts VM sizes to an approved list (cost control). The effect is fixed (Deny). Configure listOfAllowedSKUs."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = ["listOfAllowedSKUs"]
      default_enforce              = true
      identity_role_definition_ids = []
    }
    audit_custom_rbac_roles = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/a451c1ef-c6ca-483d-87ed-f49761e3ffb5"
      is_set                       = false
      display_name                 = "Audit usage of custom RBAC roles"
      category                     = "General"
      description                  = "Surfaces custom RBAC roles so privileged access stays reviewable."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Disabled"]
      default_effect               = "Audit"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }

    # ---------- Storage ----------
    storage_secure_transfer = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"
      is_set                       = false
      display_name                 = "Secure transfer to storage accounts should be enabled"
      category                     = "Storage"
      description                  = "Requires HTTPS-only access to storage accounts."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    storage_deny_public_access = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751"
      is_set                       = false
      display_name                 = "Storage account public access should be disallowed"
      category                     = "Storage"
      description                  = "Blocks anonymous public read access to blob containers."
      effect_parameter             = "effect"
      allowed_effects              = ["audit", "Audit", "deny", "Deny", "disabled", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    storage_minimum_tls = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0"
      is_set                       = false
      display_name                 = "Storage accounts should have the specified minimum TLS version"
      category                     = "Storage"
      description                  = "Enforces a TLS floor on storage accounts (defaults to TLS1_2)."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = { minimumTlsVersion = "TLS1_2" }
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    storage_restrict_network_access = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/34c877ad-507e-4c82-993e-3452a6e0ad3c"
      is_set                       = false
      display_name                 = "Storage accounts should restrict network access"
      category                     = "Storage"
      description                  = "Flags storage accounts whose firewall default action is Allow. Audit by default: denying breaks common bootstrap flows, escalate deliberately."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Audit"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }

    # ---------- Key Vault ----------
    keyvault_soft_delete = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d"
      is_set                       = false
      display_name                 = "Key vaults should have soft delete enabled"
      category                     = "Key Vault"
      description                  = "Requires soft delete so deleted vaults and secrets are recoverable."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    keyvault_purge_protection = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/0b60c0b2-2dc2-4e1c-b5c9-abbed971de53"
      is_set                       = false
      display_name                 = "Key vaults should have deletion protection enabled"
      category                     = "Key Vault"
      description                  = "Flags vaults without purge protection. Audit by default: Deny blocks legitimate short-lived vaults, escalate deliberately where vaults hold production material."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Audit"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    keyvault_firewall_enabled = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/55615ac9-af46-4a59-874e-391cc3dfb490"
      is_set                       = false
      display_name                 = "Azure Key Vault should have firewall enabled or public network access disabled"
      category                     = "Key Vault"
      description                  = "Requires a vault firewall (default action Deny) or public network access off. A firewalled vault with allow-listed IPs stays compliant."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Deny", "Disabled"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }

    # ---------- Network / compute ----------
    nic_no_public_ips = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"
      is_set                       = false
      display_name                 = "Network interfaces should not have public IPs"
      category                     = "Network"
      description                  = "Blocks public IPs directly on NICs (the effect is fixed Deny); publish through load balancers, gateways, or Bastion instead."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    subnet_nsg = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517"
      is_set                       = false
      display_name                 = "Subnets should be associated with a Network Security Group"
      category                     = "Security Center"
      description                  = "Surfaces subnets with no NSG attached."
      effect_parameter             = "effect"
      allowed_effects              = ["AuditIfNotExists", "Disabled"]
      default_effect               = "AuditIfNotExists"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    vm_management_ports_closed = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/22730e10-96f6-4aac-ad84-9383d35b5917"
      is_set                       = false
      display_name                 = "Management ports should be closed on your virtual machines"
      category                     = "Security Center"
      description                  = "Surfaces VMs with open management ports (RDP/SSH) exposed to the internet."
      effect_parameter             = "effect"
      allowed_effects              = ["AuditIfNotExists", "Disabled"]
      default_effect               = "AuditIfNotExists"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }

    # ---------- App Service / SQL ----------
    appservice_https_only = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/a4af4a39-4135-47fb-b175-47fbdf85311d"
      is_set                       = false
      display_name                 = "App Service apps should only be accessible over HTTPS"
      category                     = "App Service"
      description                  = "Requires HTTPS-only on App Service apps."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Disabled", "Deny"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    appservice_latest_tls = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/f0e6e85b-9b9f-4a4b-b67b-f730d42f1b0b"
      is_set                       = false
      display_name                 = "App Service apps should use the latest TLS version"
      category                     = "App Service"
      description                  = "Surfaces App Service apps below the latest TLS version."
      effect_parameter             = "effect"
      allowed_effects              = ["AuditIfNotExists", "Disabled"]
      default_effect               = "AuditIfNotExists"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    sql_minimum_tls = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/32e6bbec-16b6-44c2-be37-c5b672d103cf"
      is_set                       = false
      display_name                 = "Azure SQL Database should be running TLS version 1.2 or newer"
      category                     = "SQL"
      description                  = "Enforces a TLS floor on Azure SQL logical servers."
      effect_parameter             = "effect"
      allowed_effects              = ["Audit", "Disabled", "Deny"]
      default_effect               = "Deny"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }

    # ---------- Tags ----------
    # The require-tag pair have a FIXED Deny effect, so their audit-style rollout lever is enforcement
    # mode: they default to enforce = false (DoNotEnforce, compliance is evaluated and reported but
    # nothing is blocked). Set enforce = true per entry when ready to hard-require the tag.
    require_tag_on_resource_groups = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
      is_set                       = false
      display_name                 = "Require a tag on resource groups"
      category                     = "Tags"
      description                  = "Requires the named tag on resource groups (fixed Deny; rolled out in DoNotEnforce by default). Configure tagName."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = ["tagName"]
      default_enforce              = false
      identity_role_definition_ids = []
    }
    require_tag_on_resources = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"
      is_set                       = false
      display_name                 = "Require a tag on resources"
      category                     = "Tags"
      description                  = "Requires the named tag on resources (fixed Deny; rolled out in DoNotEnforce by default). Configure tagName."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = ["tagName"]
      default_enforce              = false
      identity_role_definition_ids = []
    }
    inherit_tag_from_rg = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070"
      is_set                       = false
      display_name                 = "Inherit a tag from the resource group if missing"
      category                     = "Tags"
      description                  = "Modify policy: copies the named tag from the resource group onto resources missing it. The assignment gets a system-assigned identity and the module grants it the Contributor role the definition requires. Configure tagName; module-level location is required."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = ["tagName"]
      default_enforce              = true
      identity_role_definition_ids = ["b24988ac-6180-42a0-ab88-20f7382dd24c"] # Contributor, per the definition's roleDefinitionIds
    }

    # ---------- Monitoring / benchmark ----------
    activity_log_profile = {
      policy_id                    = "/providers/Microsoft.Authorization/policyDefinitions/7796937f-307b-4598-941c-67d3a05ebfe7"
      is_set                       = false
      display_name                 = "Azure subscriptions should have a log profile for Activity Log"
      category                     = "Monitoring"
      description                  = "Surfaces subscriptions not exporting the Activity Log."
      effect_parameter             = "effect"
      allowed_effects              = ["AuditIfNotExists", "Disabled"]
      default_effect               = "AuditIfNotExists"
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
    mcsb = {
      policy_id                    = "/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8"
      is_set                       = true
      display_name                 = "Microsoft cloud security benchmark"
      category                     = "Security Center"
      description                  = "Assigns the full MCSB initiative (audit-natured) for broad security compliance visibility; Microsoft maintains its ~240 member policies."
      effect_parameter             = null
      allowed_effects              = []
      default_effect               = null
      default_parameters           = {}
      required_parameters          = []
      default_enforce              = true
      identity_role_definition_ids = []
    }
  }
}
