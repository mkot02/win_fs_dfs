#!powershell

#AnsibleRequires -CSharpUtil Ansible.Basic


$spec = @{
    options = @{
        name = @{ type = "str" }
        folders = @{
            type = "list"
            elements = "dict"
            options = @{
                name = @{ type = "str"; required = $true }
                content_path = @{ type = "path"; required = $true }
                description = @{ type = "str" }
                dfsn_path = @{ type = "str" }
                exclude_files = @{ type = "str" }
                exclude_dirs = @{ type = "str" }
            }
        }
        members = @{ type = "list" }
        topology = @{ type = "str"; default = "mesh"; choices = @("mesh") }
        description = @{ type = "str" }
        staging_quota = @{ type = "int"; default = 4096 }
        conflict_and_deleted_quota = @{ type = "int"; default = 4096 }
        state = @{ type = "str"; default = "present"; choices = @("absent", "present") }
    }
    required_if = @(
        @("state", "present", @("name", "members", "folders")),
        @("state", "absent", @("name"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$param_name = $module.Params.name
$param_members = $module.Params.members
$param_folders = $module.Params.folders
$param_topology = $module.Params.topology
$param_description = $module.Params.description
$param_staging_quota = $module.Params.staging_quota
$param_conflict_and_deleted_quota = $module.Params.conflict_and_deleted_quota
$param_state = $module.Params.state
$check_mode = $module.CheckMode


<#############################################################################
    Functions
#############################################################################>

function Get-Combinations {
    param( [array]$elements )

    $combinations = @()

    ForEach($i in $elements) {
        ForEach($j in $elements) {
            if($i -ne $j) {
                $combinations += ,($i, $j)
            }

        }
    }
    return $combinations
}

function AnsibleGet-DfsrGroup {
    param( [string]$GroupName )

    try{
        $g = Get-DfsReplicationGroup -GroupName $GroupName -IncludeSysvol:$false
    }
    catch {
        $g = $null
    }

    return $g
}


function AnsibleGet-DfsrFolder {
    param (
        [string]$GroupName,
        [string]$FolderName
    )

    try{
        $f = Get-DfsReplicatedFolder -GroupName $GroupName -FolderName $FolderName
    }
    catch {
        $f = $null
    }
    
    return $f
}


function AnsibleRemove-DfsrGroup {
    param(
        [string]$GroupName,
        [switch]$CheckMode
    )

    $result = @{ success = $true; changed = $false; msg = '' }

    $dfsr_group = AnsibleGet-DfsrGroup -GroupName $GroupName
    if($dfsr_group) {
        try {
            Remove-DfsReplicationGroup `
                -GroupName $GroupName `
                -RemoveReplicatedFolders:$true `
                -Force:$true `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "group($GroupName);"
        }
        catch {
            $result.success = $false
            $result.msg = "Failed to remove replication group: $($PSItem.Exception.Message)"
        }
    }
    
    return $result
}


function AnsibleEnsure-DfsrFolders {
    param(
        [string]$GroupName,
        [string]$Description,
        [array]$Folders,
        [switch]$CheckMode
    )

    $result = @{ success = $true; changed = $false; msg = '' }

    # Ensure replication group state
    $dfsr_group = AnsibleGet-DfsrGroup -GroupName $GroupName
    if(-not $dfsr_group) {
        try {
            New-DfsReplicationGroup `
                -GroupName $GroupName `
                -Description $Description `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "group($GroupName);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to create replication group: $($PSItem.Exception.Message)" }
        }
    }
    else {
        # Ensure description state
        if($dfsr_group.Description -ne $Description) {
            try {
                Set-DfsReplicationGroup `
                    -GroupName $GroupName `
                    -Description $Description `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "group description($Description);"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to enforce 'Description' setting for group: $($PSItem.Exception.Message)" }
            }
        }
    }
    
    # Ensure folders state
    ForEach($folder in $Folders) {
        $dfsr_folder = AnsibleGet-DfsrFolder -GroupName $GroupName -FolderName $folder.name
        if(-not $dfsr_folder) {
            try {
                New-DfsReplicatedFolder `
                    -GroupName $GroupName `
                    -FolderName $folder.name `
                    -Description $folder.description `
                    -FileNameToExclude $folder.exclude_files `
                    -DirectoryNameToExclude $folder.exclude_dirs `
                    -DfsnPath $folder.dfsn_path `
                    -WhatIf:$CheckMode
                $result.changed = $true
                $result.msg += "folder($($folder.name));"
            }
            catch {
                return @{ success = $false; changed = $false; msg = "Failed to create replication folder '$($folder.name)': $($PSItem.Exception.Message)" }
            }
        }
        else {
            # Ensure description state
            if($folder.description -and ($dfsr_folder.Description -ne $folder.description)) {
                try {
                    Set-DfsReplicatedFolder `
                        -GroupName $GroupName `
                        -Description $Description `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "folder description($($folder.name));"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'Description' setting for folder '$($folder.name)': $($PSItem.Exception.Message)" }
                }
            }

            # Ensure dns_path state
            if($folder.dfsn_path -and ($dfsr_folder.DfsnPath -ne $folder.dfsn_path)) {
                try {
                    Set-DfsReplicatedFolder `
                        -GroupName $GroupName `
                        -DfsnPath $folder.dfsn_path `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "folder dns_path($($folder.name));"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'DfsnPath' setting for folder '$($folder.name)': $($PSItem.Exception.Message)" }
                }
            }

            # Ensure exclude_files state
            if($folder.exclude_files -and ($dfsr_folder.FileNameToExclude -ne $folder.exclude_files)) {
                try {
                    Set-DfsReplicatedFolder `
                        -GroupName $GroupName `
                        -FileNameToExclude $folder.exclude_files `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "folder exclude_files($($folder.name));"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'FileNameToExclude' setting for folder '$($folder.name)': $($PSItem.Exception.Message)" }
                }
            }

            # Ensure exclude_dirs state
            if($folder.exclude_dirs -and ($dfsr_folder.DirectoryNameToExclude -ne $folder.exclude_dirs)) {
                try {
                    Set-DfsReplicatedFolder `
                        -GroupName $GroupName `
                        -DirectoryNameToExclude $folder.exclude_dirs `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "folder exclude_dirs($($folder.name));"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'DirectoryNameToExclude' setting for folder '$($folder.name)': $($PSItem.Exception.Message)" }
                }
            }
        }
    }
    
    return $result
}


function AnsibleEnsure-DfsrMembers {
    param(
        [string]$GroupName,
        [array]$Folders,
        [array]$Members,
        [string]$ReplicationTopology,
        [int]$StagingQuota,
        [int]$ConflictAndDeletedQuota,
        [switch]$CheckMode
    )

    $result = @{ success = $true; changed = $false; msg = '' }

    # Make sure that group exists
    $dfsr_group = AnsibleGet-DfsrGroup -GroupName $GroupName
    if(-not $dfsr_group) {
        if($CheckMode) {
            # In check mode set changed to true if folder doesn't exist. It will be created anyway
            return @{ success = $true; changed = $true; msg = "" }
        }
        else {
            return @{ success = $false; changed = $false; msg = "Failed to configure replication members: group '$GroupName' doesn't exists" }
        }
    }

    # Get list of current members and create lists of member to add and remove
    $dfsr_members = Get-DfsrMember -GroupName $GroupName
    $members_add = $Members | Where-Object { $dfsr_members.DnsName -notcontains $_ }
    $members_rem = $dfsr_members | Where-Object { $Members -notcontains $_.DnsName}

    # Remove not wanted member from replication group
    ForEach($member in $members_rem) {
        # Get DnsName from dict
        $member = $member.DnsName
        try {
            Remove-DfsrMember `
                -GroupName $GroupName `
                -ComputerName $member `
                -Force `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "rm member($member);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to remove member '$member' from group '$GroupName': $($PSItem.Exception.Message)" }
        }
    }

    # Add missing members to replication group
    ForEach($member in $members_add) {
        try {
            Add-DfsrMember `
                -GroupName $GroupName `
                -ComputerName $member `
                -WhatIf:$CheckMode
            $result.changed = $true
            $result.msg += "add member($member);"
        }
        catch {
            return @{ success = $false; changed = $false; msg = "Failed to add member '$member' to group '$GroupName': $($PSItem.Exception.Message)" }
        }
    }

    # Set membership options for each member in each folder.
    # Set first member from list as primary member
    ForEach($folder in $Folders) {
        # Check if folder exists
        $dfsr_folder = AnsibleGet-DfsrFolder -GroupName $GroupName -FolderName $folder.name

        if(-not $dfsr_folder) {
            if($CheckMode) {
                # In check mode set changed to true if folder doesn't exist. It will be created anyway
                return @{ success = $true; changed = $true; msg = "" }
            }
            else {
                return @{ success = $false; changed = $false; msg = "Failed to configure replication members for folder '$($folder.name)': folder doesn't exists" }
            }
        }

        ForEach($member in $Members) {
            # Get membership without try/except. It should exist by this point
            $dfsr_membership = Get-DfsrMembership -GroupName $GroupName -ComputerName $member | Where-Object { $_.FolderName -eq $folder.name }

            if($StagingQuota -and ($StagingQuota -ne $dfsr_membership.StagingPathQuotaInMB)) {
                try {
                    Set-DfsrMembership `
                        -GroupName $GroupName `
                        -FolderName $folder.name `
                        -ComputerName $member `
                        -ContentPath $folder.content_path `
                        -StagingPathQuota $StagingQuota `
                        -Force:$true `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "member staging_quota($member);"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'StagingPathQuota' setting: $($PSItem.Exception.Message)" }
                }
            }
            
            if($ConflictAndDeletedQuota -and ($ConflictAndDeletedQuota -ne $dfsr_membership.ConflictAndDeletedQuotaInMB)) {
                try {
                    Set-DfsrMembership `
                        -GroupName $GroupName `
                        -FolderName $folder.name `
                        -ComputerName $member `
                        -ContentPath $folder.content_path `
                        -ConflictAndDeletedQuota $ConflictAndDeletedQuota `
                        -Force:$true `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "member conflicted_quota($member);"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'ConflictAndDeletedQuota' setting: $($PSItem.Exception.Message)" }
                }
            }
            
            if($folder.dfsn_path -ne $dfsr_membership.DfsnPath) {
                try {
                    Set-DfsrMembership `
                        -GroupName $GroupName `
                        -FolderName $folder.name `
                        -ComputerName $member `
                        -ContentPath $folder.content_path `
                        -DfsnPath $folder.dfsn_path `
                        -Force:$true `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "member dfsn_path($member);"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to enforce 'DfsnPath' setting: $($PSItem.Exception.Message)" }
                }
            }
            
            # Ensure primary member
            if(($member -eq $Members[0]) -and (-not $dfsr_membership.PrimaryMember)) {
                try {
                    Set-DfsrMembership `
                        -GroupName $GroupName `
                        -FolderName $folder.name `
                        -ComputerName $member `
                        -PrimaryMember:$true `
                        -Force:$true `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "member primary($member);"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to configure primary member for folder '$($folder.name)': $($PSItem.Exception.Message)" }
                }
            }

            # Update membership configuration
            Update-DfsrConfigurationFromAD -ComputerName $member
        }
    }

    # Ensure replication topology
    if($ReplicationTopology.ToLower() -eq "mesh") {
        $combinations = Get-Combinations $members

        ForEach($pair in $combinations) {
            $src_member = $pair[0]
            $dst_member = $pair[1]

            # Check if connection exists
            $conn = Get-DfsrConnection `
                -GroupName $GroupName `
                -SourceComputerName $src_member `
                -DestinationComputerName $dst_member

            if(-not $conn) {
                try {
                    Add-DfsrConnection `
                        -GroupName $GroupName `
                        -SourceComputerName $src_member `
                        -DestinationComputerName $dst_member `
                        -WhatIf:$CheckMode
                    $result.changed = $true
                    $result.msg += "connection($src_member - $dst_member);"
                }
                catch {
                    return @{ success = $false; changed = $false; msg = "Failed to create connection between '$src_member' - '$dst_member': $($PSItem.Exception.Message)" }
                }
            }
        }
    }

    return $result
}


<#############################################################################
    Main script
#############################################################################>

# Check if DFSR feature is installed
$dfsn_feature = Get-WindowsFeature -Name FS-DFS-Replication
if($dfsn_feature.InstallState -ne 'Installed') {
    $module.FailJson("'FS-DFS-Replication' feature is not installed. Install this feature to use this module")
}

if($param_state -eq 'absent') {
    $result = AnsibleRemove-DfsrGroup -GroupName $param_name -CheckMode:$check_mode

    # Check if previous step succeded
    if(-not $result.success) {
        $module.FailJson($result.msg)
    }
}
else {
    $result_f = AnsibleEnsure-DfsrFolders `
        -GroupName $param_name `
        -Description $param_description `
        -Folders $param_folders `
        -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_f.success) {
        $module.FailJson($result_f.msg)
    }

    # Ensure root targets
    $result_m = AnsibleEnsure-DfsrMembers `
        -GroupName $param_name `
        -Folders $param_folders `
        -Members $param_members `
        -ReplicationTopology $param_topology `
        -StagingQuota $param_staging_quota `
        -ConflictAndDeletedQuota $param_conflict_and_deleted_quota `
        -CheckMode:$check_mode
    # Check if previous step succeded
    if(-not $result_m.success) {
        $module.FailJson($result_m.msg)
    }
    
    $result = @{
        changed = ($result_f.changed -or $result_m.changed)
        msg = $result_f.msg + $result_m.msg
    }
}

$module.Result.changed = $result.changed
$module.Result.msg = $result.msg
$module.ExitJson()