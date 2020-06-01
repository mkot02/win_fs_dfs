# Ansible Collection - win_fs_dfs
Ansible Collection for managing Windows Server DFS Namespace and DFS Replication.

## Included content
Filters:
- `unc_path`

Modules:
- `win_dfs_namespace_root`
- `win_dfs_namespace_folder`
- `win_dfs_replication_group`

Roles:
- `win_dfs_setup`

## Installation and Usage
### Installing collection from Ansible Galaxy
Before using this collection, you need to install it using Ansible Galaxy CLI:
```
ansible-galaxy collection install mkot02.win_fs_dfs
```

### Using collection
You can create DFS Namespaces and Folders and configure replication by using [win_dfs_setup](./roles/win_dfs_setup/README.md) role.

## License
MIT