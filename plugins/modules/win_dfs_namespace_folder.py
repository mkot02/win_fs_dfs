#!/usr/bin/python
# -*- coding: utf-8 -*-

ANSIBLE_METADATA = {'metadata_version': '1.1',
                    'status': ['preview'],
                    'supported_by': 'community'}


DOCUMENTATION = r'''
module: win_dfs_namespace_folder
short_description: Set up a DFS folder.

description:
  - This module creates/manages Windows DFS namespace folders.
  - Prior to using this module it's required to install File Server with
    FS-DFS-Namespace feature and create shares for namespace folders on all member servers.
  - For more details about DFSN see
    U(https://docs.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview)

notes:
  - Setting state for targets is not implemented
  - Setting referral priority options is not implemented

options:
  path:
    description:
      - UNC path for the folder
    type: str
    required: true
  targets:
    description:
      - List of UNC paths for DFS folder targets.
      - Targets which are configured in namespace folder and are not listed here, will be removed from namespace folder.
      - Required when C(state) is not C(absent).
      - Target hosts must be referenced by FDQN if DFSN server has not configured with C(UseFQDN) option (https://support.microsoft.com/de-de/help/244380/how-to-configure-dfs-to-use-fully-qualified-domain-names-in-referrals)
    type: list
  description:
    description:
      - Description of DFS folder
    type: str
  state:
    description:
      - When C(present), the folder will be created if not exists.
      - When C(absent), the folder will be removed.
      - When C(online), the folder will be created if not exists and will be put in online state.
      - When C(offline), the folder will be created if not exists and will be put in offline state.
      - When C(online)/C(offline) only state of folder will be set, not the state of targets.
    choices:
      - present
      - absent
      - online
      - offline
    default: present
  insite_referrals:
    description:
      - Indicates whether a DFS namespace server provides a client only with referrals that are in the same site as the client.
      - If this value is C(yes), the DFS namespace server provides only in-site referrals.
      - If this value is C(no), the DFS namespace server provides in-site referrals first, then other referrals.
    type: bool
    default: false
  target_failback:
    description:
      - Indicates whether a DFS namespace uses target failback.
      - If a client attempts to access a target on a server and that server is not available, the client fails over to another referral.
      - If this value is C(yes), once the first server becomes available again, the client fails back to the first server.
      - If this value is C(no), the DFS namespace server does not require the client to fail back to the preferred.
    type: bool
    default: false
  ttl:
    description:
      - TTL interval, in seconds, for referrals. Clients store referrals to targets for this length of time.
    type: int
    default: 1800

seealso:
- module: win_share
- module: win_dfs_namespace_root
- module: win_dfs_replication_group

author:
  - Marcin Kotarba (@mkot02)
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
- name: Create DFS folder
  win_dfs_namespace_folder:
    path: '\\domain.exmaple.com\dfs\folder'
    targets:
      - '\\dc1.domain.exmaple.com\dfs\folder'
      - '\\dc2.domain.exmaple.com\dfs\folder'
      - '\\dc3.domain.exmaple.com\dfs\folder'
    description: "DFS Folder"
    state: present

- name: Remove DFS folder
  win_dfs_namespace_folder:
    path: '\\domain.exmaple.com\dfs\folder'
    state: absent
'''