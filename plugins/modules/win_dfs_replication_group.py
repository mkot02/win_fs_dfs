#!/usr/bin/python
# -*- coding: utf-8 -*-

ANSIBLE_METADATA = {'metadata_version': '1.1',
                    'status': ['preview'],
                    'supported_by': 'community'}


DOCUMENTATION = r'''
module: win_dfs_replication_group
short_description: Set up a DFS replication.

description:
  - This module creates/manages Windows DFS replication groups and folders.
  - Prior to using this module it's required to install File Server with FS-DFS-Replication feature.
  - For more details about DFSR see
    U(https://docs.microsoft.com/en-us/windows-server/storage/dfs-replication/dfsr-overview)

notes:
  - Custom StagingPath not implemented
  - ReadyOnly mode not implemented
  - Remote Differential Compression (RDC) settings not implemented

options:
  name:
    description:
      - Name of the replication group to configure
    type: str
    required: true
  folders:
    description:
      - List of folders to maintain in the group.
      - Folders existing in replication group and not existing in list will NOT be removed.
      - Valid attributes are:
      - '- C(name) (string): = name of the replication folder to add; this attribute is required'
      - '- C(content_path) (string): = local path for folder; this path must be the same for all members; this attribute is required'
      - '- C(description) (string): description of replication folder'
      - '- C(dfsn_path) (string): DFSN path; this attribute is just an information'
      - '- C(exclude_files) (string): comma-separated list of wildcards for file names to exclude from replication'
      - '- C(exclude_dirs) (string): comma-separated list of wildcards for directory names to exclude from replication'
    type: list
  members:
    description:
      - List of member of replication group.
      - Members existing in replication group and not existing in list will be removed.
    type: list
  description:
    description:
      - Description of replication group.
    type: str
  topology:
    description:
      - Topology of connection in replication group.
      - C(mesh) - each member of replication group has connection with other members
    type: str
    choices: ['mesh']
    default: mesh
  staging_quota:
    description:
      - Maximum size in MB for the staging folder for all members of replication group
    type: int
    default: 4096
  conflict_and_deleted_quota:
    description:
      - Maximum size in MB for the C(ConflictsAndDeleted) folder for all members of replication group
    type: int
    default: 4096
  state:
    description:
      - When C(present), the namespace will be created if not exists.
      - When C(absent), the namespace will be removed.
    choices:
      - present
      - absent
    default: present

seealso:
- module: win_share
- module: win_dfs_namespace_root
- module: win_dfs_namespace_folder

author:
    - Marcin Kotarba <@mkot02>
'''

RETURN = r'''
msg:
  description:
    - if success: list of changes made by the module separated by semicolon
    - if failure: reason why module failed
  returned: always
  type: str
'''

EXAMPLES = r'''
- name: Configure DFS replication group
  win_dfs_replication_group:
    name: dfsr
    members:
      - dc1.domain.exmaple.com
      - dc2.domain.exmaple.com
      - dc3.domain.exmaple.com
    topology: mesh
    folders:
      - name: dfs_folder
        content_path: 'C:\DFS\dfs_folder'
        dfsn_path: '\\domain.exmaple.com\dfs\dfs_folder'
    staging_quota: 8192
    state: present

- name: Remove DFS replication group
  win_dfs_replication_group:
    name: dfsr
    state: absent
'''