# win_dfs_setup
This role setups DFS Namespace and DFS Replication (if running on multiple hosts) for AD File Server.

## Requirements
Modules:
  - `win_dfs_namespace_root`
  - `win_dfs_namespace_folder`
  - `win_dfs_replication_group`

## Role Variables
| Variable Name | Description | Default Value | Variable Type | Required |
| --- | --- | --- | --- | --- |
| domain_name | Domain in which DFS will be created | - | string | yes |
| win_dfs_namespaces | (1) List of namespaces to create | - | list | yes |
| win_dfsr_stage_size | Size in MB of DFSR staging folder | 4096 | int | no |
| win_dfsr_conflicted_size | Size in MB of DFSR conflicted and deleted folder | 4096 | int | no |

> (1) Detailed description of `win_dfs_namespaces` variable:
```yaml
                                            # - optional
                                            # = required
win_dfs_namespaces:                         #
  - name: namespace                         # =name                 (string):  name of the namespace to manage
    description: DFS Namespace Root         # -description          (string):  description of the namespace
    root_path: 'C:\DFS'                     # =root_path            (string):  parent path to namespace root and all folders
    shares:                                 # =shares               (list)  :  list of folders to create in the namespace
      - name: folder                        # =shares.name          (string):  name of the folder to manage
        description: Folder decsription     # -shares.description   (string):  description of the folder
        exclude_files: "~*, *.bak, *.tmp"   # -shares.exclude_files (string):  comma-separated list of wildcards for excluding files from replication
        exclude_dirs: "Temp"                # -shares.exclude_dirs  (string):  comma-separated list of wildcards for excluding directories from replication
    options:                                # -options              (dict)  :  additionals options for DFS namespace
      access_based_enumeration: true
      insite_referrals: false
      root_scalability: false
      site_costing: true
      target_failback: false
      ttl: 300
```

## Dependencies
None

## Example Playbook
```yaml
- hosts: win_domain_controllers
  roles:
    - win_dfs_setup
```

## License
MIT

## Author Information
Marcin Kotarba <@mkot02>