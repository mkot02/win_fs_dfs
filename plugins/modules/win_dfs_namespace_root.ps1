#!powershell

#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        path = @{ type = "path" }
        targets = @{ type = "list" }
        type = @{ type = "str"; default = "DomainV2"; choices = @("DomainV1", "DomainV2", "Standalone") }
        description = @{ type = "str" }
        site_costing = @{ type = "bool"; default = $false}
        insite_referrals = @{ type = "bool"; default = $false}
        access_based_enumeration = @{ type = "bool"; default = $false}
        root_scalability = @{ type = "bool"; default = $false}
        target_failback = @{ type = "bool"; default = $false}
        ttl = @{ type = "int"; default = 300 }
        state = @{ type = "str"; default = "present"; choices = @("absent", "present", "online", "offline") }
    }
    required_if = @(
        @("state", "present", @("path", "targets")),
        @("state", "online", @("path", "targets")),
        @("state", "offline", @("path", "targets")),
        @("state", "absent", @("path"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$param_path = $module.Params.path
$param_targets = $module.Params.targets
$param_type = $module.Params.type
$param_description = $module.Params.description
$param_site_costing = $module.Params.site_costing
$param_insite_referrals = $module.Params.insite_referrals
$param_access_based_enumeration = $module.Params.access_based_enumeration
$param_root_scalability = $module.Params.root_scalability
$param_target_failback = $module.Params.target_failback
$param_ttl = $module.Params.ttl
$param_state = $module.Params.state
$check_mode = $module.CheckMode


<#############################################################################
    Functions
#############################################################################>

function AnsibleGet-DfsnNamespace {
    param ( $NamespacePath )

    # Check if namespace already exists
    try {
        $ns = Get-DfsnRoot -Path $NamespacePath
    }
    catch {
        $ns = $null
    }

    return $ns
}


function AnsibleRemove-DfsnNamespace {
    param (
        [string]$NamespacePath,
        [switch]$CheckMode
    )

    $dfsn_root = AnsibleGet-DfsnNamespace -NamespacePath $NamespacePath

    # Return success and no change if namespace was non-existent already,
    # other wise try to remove namespace.
    if(-not $dfsn_root) {
        $result = @{ success = $true; changed = $false; msg = '' }
    }
    else {
        try {
            Remove-DfsnRoot -Path $NamespacePath -Force -WhatIf:$CheckMode
            $result =  @{ success = $true; changed = $true; msg = "namespace($NamespacePath);" }
        }
        catch {
            $result =  @{ success = $false; changed = $false; msg = "Failed to remove namespace: $($PSItem.Exception.Message)" }
        }
    }

    return $result
}


function AnsibleEnsure-DfsnNamespaceTargets {
    param (
        [string]$NamespacePath,
        [array]$Targets,
        [switch]$CheckMode
    )

    $dfsn_root = AnsibleGet-DfsnNamespace -NamespacePath $NamespacePath
    $result = @{ success = $true; changed = $false; msg = "" }

    # Make sure that namespace exists
    if(-not $dfsn_root) {
        if($CheckMode) {
            # In check mode set changed to true if namespace doesn't exist. It will be created anyway
            return @{ success = $true; changed = $true; msg = "" }
        }
        else {
            return @{ success = $false; changed = $false; msg = "Failed to enforce root targets: namespace doesn't exists" }
        }
    }

    # Get current targets and parse result to dict
    $current_targets = @{}
    $dfsn_targets = Get-DfsnRootTarget -Path $NamespacePath
    ForEach($target in $dfsn_targets) {
        $t_host_full = $target.TargetPath.Split('\')[2]
        $t_host_short = $t_host_full.Split('.')[0]
        $t_dfsn = $target.TargetPath.Split('\')[3]

        # Set FQDN to null if full doesn't contain domain name.
        $t_host_fqdn = if($t_host_short -eq $t_host_full) {$null} else {$t_host_full}
        $current_targets[$t_host_short] = @{ns=$t_dfsn; fqdn=$t_host_fqdn; path=$target.TargetPath}
    }

    # Parse list of targets to dict
    $wanted_targets = @{}
    ForEach($target in $Targets) {
        $t_host_full = $target.Split('\')[2]
        $t_host_short = $t_host_full.Split('.')[0]
        $t_dfsn = $target.Split('\')[3]

        # Set FQDN to null if full doesn't contain domain name.
        $t_host_fqdn = if($t_host_short -eq $t_host_full) {$null} else {$t_host_full}
        $wanted_targets[$t_host_short] = @{ns=$t_dfsn; fqdn=$t_host_fqdn; path=$target}
    }

    # This way of doing it has some limitations when namespace consist servers
    # with the same hostname but different domains or subdomains.
    # For now it should conver most of usecases, in the future dicts created eariler may be useful.
    $targets_add = $wanted_targets.Keys | Where-Object {$current_targets.Keys -notcontains $_}
    $targets_rem = $current_targets.Keys | Where-Object {$wanted_targets.Keys -notcontains $_}

    # Remove root targets that are not on wanted list
    ForEach($target in $targets_rem) {
        try {
            Remove-DfsnRootTarget `
                -Path $NamespacePath `
                -TargetPath $current_targets.$target.path `
                -Confirm:$false `
                -Cleanup:$true `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "rm target($($current_targets.$target.path));"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to remove root target: $($PSItem.Exception.Message)" }
        }
    }

    # Add missing root targets
    ForEach($target in $targets_add) {
        try {
            New-DfsnRootTarget `
                -Path $NamespacePath `
                -TargetPath $wanted_targets.$target.path `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "add target($($wanted_targets.$target.path));"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to add root target: $($PSItem.Exception.Message)" }
        }
    }
    return $result
}


function AnsibleEnsure-DfsnNamespace {
    param (
        [string]$NamespacePath,
        [string]$TargetPath,
        [string]$Type,
        [string]$Description,
        [switch]$SiteCosting,
        [switch]$InsiteReferrals,
        [switch]$AccessBasedEnumeration,
        [switch]$RootScalability,
        [switch]$TargetFailback,
        [int]$TTL,
        [switch]$CheckMode
    )

    $dfsn_root = AnsibleGet-DfsnNamespace -NamespacePath $NamespacePath
    $result = @{ success = $true; changed = $false; msg = "" }

    # Make sure that namespace exists
    if(-not $dfsn_root) {
        try {
            # Create new namespace using first target from list as root target
            New-DfsnRoot `
                -Path $NamespacePath `
                -Type $Type `
                -TargetPath $TargetPath `
                -Description $Description `
                -TimeToLiveSec $TTL `
                -EnableSiteCosting $SiteCosting `
                -EnableInsiteReferrals $InsiteReferrals `
                -EnableAccessBasedEnumeration $AccessBasedEnumeration `
                -EnableRootScalability $RootScalability `
                -EnableTargetFailback $TargetFailback `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "namespace($NamespacePath);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to create namespace: $($PSItem.Exception.Message)" }
        }
    }
    else {
        # It seems that namespace exists. Let's check if all settings are correct
        $result = @{ success = $true; changed = $false; msg = '' }

        # Fail if user wants to change type of namespace
        if($dfsn_root.Type.Replace(' ','') -ne $Type) {
            return @{ success = $false; changed = $false; msg = "Not possible to change type of existing namespace" }
        }

        # Ensure TTL state
        if($dfsn_root.TimeToLiveSec -ne $TTL) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -TimeToLiveSec $TTL `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace ttl($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'TTL' setting: $($PSItem.Exception.Message)" }
            }
        }

        # Ensure description state
        if($dfsn_root.Description -ne $Description) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -Description $Description `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace description($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'Description' setting: $($PSItem.Exception.Message)" }
            }
        }

        # Ensure flags state
        $f_access_based_enumeration = $dfsn_root.Flags -contains "AccessBased Enumeration"
        if($f_access_based_enumeration -ne $AccessBasedEnumeration) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -EnableAccessBasedEnumeration $AccessBasedEnumeration `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace access_based_enumeration($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'AccessBasedEnumeration' flag: $($PSItem.Exception.Message)" }
            }
        }

        $f_insite_referrals = $dfsn_root.Flags -contains "Insite Referrals"
        if($f_insite_referrals -ne $InsiteReferrals) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -EnableInsiteReferrals $InsiteReferrals `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace insite_referrals($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'InsiteReferrals' flag: $($PSItem.Exception.Message)" }
            }
        }

        $f_root_scalability = $dfsn_root.Flags -contains "Root Scalability"
        if($f_root_scalability -ne $RootScalability) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -EnableRootScalability $RootScalability `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace root_scalability($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'RootScalability' flag: $($PSItem.Exception.Message)" }
            }
        }

        $f_site_costing = $dfsn_root.Flags -contains "Site Costing"
        if($f_site_costing -ne $SiteCosting) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -EnableSiteCosting $SiteCosting `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace site_costing($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'SiteCosting' flag: $($PSItem.Exception.Message)" }
            }
        }

        $f_target_failback = $dfsn_root.Flags -contains "Target Failback"
        if($f_target_failback -ne $TargetFailback) {
            try {
                Set-DfsnRoot `
                    -Path $NamespacePath `
                    -EnableTargetFailback $TargetFailback `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "namespace target_failback($NamespacePath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'TargetFailback' flag: $($PSItem.Exception.Message)" }
            }
        }
    }

    return $result
}


function AnsibleEnsure-DfsnNamespaceState {
    param (
        [string]$NamespacePath,
        [switch]$Online,
        [switch]$CheckMode
    )

    $dfsn_root = AnsibleGet-DfsnNamespace -NamespacePath $NamespacePath

    # Make sure that namespace exists
    if(-not $dfsn_root) {
        if($CheckMode) {
            # In check mode set changed to true if namespace doesn't exist. It will be created anyway
            return @{ success = $true; changed = $true; msg = "" }
        }
        else {
            return @{ success = $false; changed = $false; msg = "Failed to enforce state: namespace doesn't exists" }
        }
    }

    $dfsn_root_is_online = $dfsn_root -eq 'Online'
    if($dfsn_root_is_online -eq $Online) {
        $desired_state = if($Online) {"Online"} else {"Offline"}
        try {
            Set-DfsnRoot `
                -Path $NamespacePath `
                -State $desired_state `
                -WhatIf:$CheckMode
            $result = @{ success = $true; changed = $true; msg = '' }
            $result.msg += "namespace state($NamespacePath);"
        }
        catch {
            $result = @{ success = $false; changed = $false; msg = "Failed to enforce state: $($PSItem.Exception.Message)" }
        }
    }

    return $result
}


<#############################################################################
    Main script
#############################################################################>

# Check if DFSN feature is installed
$dfsn_feature = Get-WindowsFeature -Name FS-DFS-Namespace
if($dfsn_feature.InstallState -ne 'Installed') {
    $module.FailJson("'FS-DFS-Namespace' feature is not installed. Install this feature to use this module")
}

if($param_state -eq 'absent') {
    $result = AnsibleRemove-DfsnNamespace `
        -NamespacePath $param_path `
        -CheckMode:$check_mode

    # Check if previous step succeded
    if(-not $result.success) {
        $module.FailJson($result.msg)
    }
}
else {
    $result_n = AnsibleEnsure-DfsnNamespace `
       -NamespacePath $param_path `
       -TargetPath $param_targets[0] `
       -Type $param_type `
       -Description $param_description `
       -TTL $param_ttl `
       -Site_costing:$param_site_costing `
       -Insite_referrals:$param_insite_referrals `
       -Access_based_enumeration:$param_access_based_enumeration `
       -Root_scalability:$param_root_scalability `
       -Target_failback:$param_target_failback `
       -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_n.success) {
        $module.FailJson($result_n.msg)
    }

    # Ensure root targets
    $result_t = AnsibleEnsure-DfsnNamespaceTargets `
        -NamespacePath $param_path `
        -Targets $param_targets `
        -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_t.success) {
        $module.FailJson($result_t.msg)
    }

    # Ensute namespace state only of state is online or offline.
    # Don't ensure state if state is present.
    if(($param_state -eq 'online') -or ($param_state -eq 'offline')) {
        $ns_online = if($param_state -eq 'online') { $true } else { $false }
        $result_s = AnsibleEnsure-DfsnNamespaceState `
            -NamespacePath $param_path `
            -Online:$ns_online `
            -CheckMode:$check_mode
        # Check if previous step succeded
        if(-not $result_s.success) {
            $module.FailJson($result_s.msg)
        }
    }

    $result = @{
        changed = ($result_n.changed -or $result_t.changed -or $result_s.changed)
        msg = $result_n.msg + $result_t.msg + $result_s.msg
    }
}

$module.Result.changed = $result.changed
$module.Result.msg = $result.msg
$module.ExitJson()