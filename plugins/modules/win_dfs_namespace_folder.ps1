#!powershell

#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        path = @{ type = "path" }
        targets = @{ type = "list" }
        description = @{ type = "str" }
        insite_referrals = @{ type = "bool"; default = $false}
        target_failback = @{ type = "bool"; default = $false}
        ttl = @{ type = "int"; default = 1800 }
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
$param_description = $module.Params.description
$param_insite_referrals = $module.Params.insite_referrals
$param_target_failback = $module.Params.target_failback
$param_state = $module.Params.state
$param_ttl = $module.Params.ttl
$check_mode = $module.CheckMode


<#############################################################################
    Functions
#############################################################################>

function AnsibleGet-DfsnFolder {
    param ( $FolderPath )

    # Check if folder already exists
    try {
        $f = Get-DfsnFolder -Path $FolderPath
    }
    catch {
        $f = $null
    }

    return $f
}


function AnsibleRemove-DfsnFolder {
    param (
        [string]$FolderPath,
        [switch]$CheckMode
    )

    $dfsn_folder = AnsibleGet-DfsnFolder -FolderPath $FolderPath

    # Return success and no change if folder was non-existent already,
    # other wise try to remove folder.
    if(-not $dfsn_folder) {
        $result = @{ success = $true; changed = $false; msg = '' }
    }
    else {
        try {
            Remove-DfsnFolder -Path $FolderPath -Force -WhatIf:$CheckMode
            $result =  @{ success = $true; changed = $true; msg = "folder($FolderPath);" }
        }
        catch {
            $result =  @{ success = $false; changed = $false; msg = "Failed to remove folder: $($PSItem.Exception.Message)" }
        }
    }

    return $result
}


function AnsibleEnsure-DfsnFolderTargets {
    param (
        [string]$FolderPath,
        [array]$Targets,
        [switch]$CheckMode
    )

    $dfsn_folder = AnsibleGet-DfsnFolder -FolderPath $FolderPath
    $result = @{ success = $true; changed = $false; msg = "" }

    # Make sure that namespace exists
    if(-not $dfsn_folder) {
        if($CheckMode) {
            # In check mode set changed to true if folder doesn't exist. It will be created anyway
            return @{ success = $true; changed = $true; msg = "" }
        }
        else {
            return @{ success = $false; changed = $false; msg = "Failed to enforce folder targets: folder doesn't exists" }
        }
    }

    # Get current targets and parse result to dict
    $current_targets = @{}
    $dfsn_targets = Get-DfsnFolderTarget -Path $FolderPath
    ForEach($target in $dfsn_targets) {
        $t_host_full = $target.TargetPath.Split('\')[2]
        $t_host_short = $t_host_full.Split('.')[0]
        $t_dfsf = $target.TargetPath.Split('\')[3]
    
        # Set FQDN to null if full doesn't contain domain name.
        $t_host_fqdn = if($t_host_short -eq $t_host_full) {$null} else {$t_host_full}
        $current_targets[$t_host_short] = @{ns=$t_dfsf; fqdn=$t_host_fqdn; path=$target.TargetPath}
    }
    
    # Parse list of targets to dict
    $wanted_targets = @{}
    ForEach($target in $Targets) {
        $t_host_full = $target.Split('\')[2]
        $t_host_short = $t_host_full.Split('.')[0]
        $t_dfsf = $target.Split('\')[3]
    
        # Set FQDN to null if full doesn't contain domain name.
        $t_host_fqdn = if($t_host_short -eq $t_host_full) {$null} else {$t_host_full}
        $wanted_targets[$t_host_short] = @{ns=$t_dfsf; fqdn=$t_host_fqdn; path=$target}
    }
    
    # This way of doing it has some limitations when namespace consist servers
    # with the same hostname but different domains or subdomains.
    # For now it should conver most of usecases, in the future dicts created eariler may be useful.
    $targets_add = $wanted_targets.Keys | Where-Object {$current_targets.Keys -notcontains $_}
    $targets_rem = $current_targets.Keys | Where-Object {$wanted_targets.Keys -notcontains $_}

    # Remove folder targets that are not on wanted list
    ForEach($target in $targets_rem) {
        try {
            Remove-DfsnFolderTarget `
                -Path $FolderPath `
                -TargetPath $current_targets.$target.path `
                -Force `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "rm target($FolderPath);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to remove folder target: $($PSItem.Exception.Message)" }
        }
    }

    # Add missing folder targets
    ForEach($target in $targets_add) {
        try {
            New-DfsnFolderTarget `
                -Path $FolderPath `
                -TargetPath $wanted_targets.$target.path `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "add target($FolderPath);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to add folder target: $($PSItem.Exception.Message)" }
        }
    }
    return $result
}


function AnsibleEnsure-DfsnFolder {
    param (
        [string]$FolderPath,
        [string]$TargetPath,
        [string]$Description,
        [switch]$InsiteReferrals,
        [switch]$TargetFailback,
        [int]$TTL,
        [switch]$CheckMode
    )

    $dfsn_folder = AnsibleGet-DfsnFolder -FolderPath $FolderPath
    $result = @{ success = $true; changed = $false; msg = "" }

    # Make sure that namespace exists
    if(-not $dfsn_folder) {
        try {
            # Create new namespace using first target from list as folder target
            New-DfsnFolder `
                -Path $FolderPath `
                -TargetPath $TargetPath `
                -Description $Description `
                -TimeToLiveSec $TTL `
                -EnableInsiteReferrals $InsiteReferrals `
                -EnableTargetFailback $TargetFailback `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg = "folder($FolderPath);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to create folder: $($PSItem.Exception.Message)" }
        }
    }
    else {
        # It seems that namespace exists. Let's check if all settings are correct
        $result = @{ success = $true; changed = $false; msg = '' }

        # Ensure TTL state
        if($dfsn_folder.TimeToLiveSec -ne $TTL) {
            try {
                Set-DfsnFolder `
                    -Path $FolderPath `
                    -TimeToLiveSec $TTL `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg = "folder ttl($FolderPath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'TTL' setting: $($PSItem.Exception.Message)" }
            }
        }

        # Ensure description state
        if($dfsn_folder.Description -ne $Description) {
            try {
                Set-DfsnFolder `
                    -Path $FolderPath `
                    -Description $Description `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg = "folder description($FolderPath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'Description' setting: $($PSItem.Exception.Message)" }
            }
        }

        $f_insite_referrals = $dfsn_folder.Flags -contains "Insite Referrals"
        if($f_insite_referrals -ne $InsiteReferrals) {
            try {
                Set-DfsnFolder `
                    -Path $FolderPath `
                    -EnableInsiteReferrals $InsiteReferrals `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg = "folder insite_referrals($FolderPath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'InsiteReferrals' flag: $($PSItem.Exception.Message)" }
            }
        }

        $f_target_failback = $dfsn_folder.Flags -contains "Target Failback"
        if($f_target_failback -ne $TargetFailback) {
            try {
                Set-DfsnFolder `
                    -Path $FolderPath `
                    -EnableTargetFailback $TargetFailback `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg = "folder target_failback($FolderPath);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'TargetFailback' flag: $($PSItem.Exception.Message)" }
            }
        }
    }

    return $result
}


function AnsibleEnsure-DfsnFolderState {
    param (
        [string]$FolderPath,
        [switch]$Online,
        [switch]$CheckMode
    )

    $dfsn_folder = AnsibleGet-DfsnFolder -FolderPath $FolderPath

    # Make sure that namespace exists
    if(-not $dfsn_folder) {
        if($CheckMode) {
            # In check mode set changed to true if namespace doesn't exist. It will be created anyway
            return @{ success = $true; changed = $true; msg = "" }
        }
        else {
            return @{ success = $false; changed = $false; msg = "Failed to enforce state: folder doesn't exists" }
        }
    }

    $dfsn_folder_is_online = $dfsn_folder -eq 'Online'
    if($dfsn_folder_is_online -eq $Online) {
        $desired_state = if($Online) {"Online"} else {"Offline"}
        try {
            Set-DfsnFolder `
                -Path $FolderPath `
                -State $desired_state `
                -WhatIf:$CheckMode
            $result = @{ success = $true; changed = $true; msg = "folder state($FolderPath);" }
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
    $result = AnsibleRemove-DfsnFolder `
        -FolderPath $param_path `
        -CheckMode:$check_mode

    # Check if previous step succeded
    if(-not $result.success) {
        $module.FailJson($result.msg)
    }
}
else {
    $result_f = AnsibleEnsure-DfsnFolder `
       -FolderPath $param_path `
       -TargetPath $param_targets[0] `
       -Description $param_description `
       -TTL $param_ttl `
       -Insite_referrals:$param_insite_referrals `
       -Target_failback:$param_target_failback `
       -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_f.success) {
        $module.FailJson($result_f.msg)
    }

    # Ensure folder targets
    $result_t = AnsibleEnsure-DfsnFolderTargets `
        -FolderPath $param_path `
        -Targets $param_targets `
        -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_t.success) {
        $module.FailJson($result_t.msg)
    }

    # Ensute folder state only of state is online or offline.
    # Don't ensure state if state is present.
    if(($param_state -eq 'online') -or ($param_state -eq 'offline')) {
        $f_online = if($param_state -eq 'online') { $true } else { $false }
        $result_s = AnsibleEnsure-DfsnFolderState `
            -FolderPath $param_path `
            -Online:$f_online `
            -CheckMode:$check_mode
        # Check if previous step succeded
        if(-not $result_s.success) {
            $module.FailJson($result_s.msg)
        }
    }

    $result = @{
        changed = ($result_f.changed -or $result_t.changed -or $result_s.changed)
        msg = $result_f.msg + $result_t.msg + $result_s.msg
    }
}

$module.Result.changed = $result.changed
$module.Result.msg = $result.msg
$module.ExitJson()