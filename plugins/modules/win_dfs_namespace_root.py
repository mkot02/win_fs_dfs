#!/usr/bin/python
# -*- coding: utf-8 -*-

ANSIBLE_METADATA = {'metadata_version': '1.1',
                    'status': ['preview'],
                    'supported_by': 'community'}


DOCUMENTATION = r'''
module: win_dfs_namespace_root
short_description: Set up a DFS namespace.

description:
  - This module creates/manages Windows DFS namespaces.
  - Prior to using this module it's required to install File Server with
    FS-DFS-Namespace feature and create shares for namespace root on all member servers.
  - For more details about DFSN see
    U(https://docs.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview)

notes:
  - Setting state for targets is not implemented
  - Setting namespace admin grants is not implemented
  - Setting referral priority options is not implemented

options:
  path:
    description:
      - UNC path for the root of a DFS namespace. This path must be unique.
    type: str
    required: true
  targets:
    description:
      - List of UNC paths for DFS root targets.
      - Targets which are configured in namespace and are not listed here, will be removed from namespace.
      - Required when C(state) is not C(absent).
      - Target hosts must be referenced by FDQN if DFSN server has not configured with C(UseFQDN) option (U(https://support.microsoft.com/de-de/help/244380/how-to-configure-dfs-to-use-fully-qualified-domain-names-in-referrals))
    type: list
  description:
    description:
      - Description of DFS namespace
    type: str
  type:
    description:
      - Type of DFS namespace
      - C(Standalone) - stand-alone namespace.
      - C(DomainV1) - Windows 2000 Server mode domain namespace.
      - C(DomainV2) - Windows Server 2008 mode domain namespace.
    choices:
      - DomainV1
      - DomainV2
      - Standalone
    default: DomainV2
  state:
    description:
      - When C(present), the namespace will be created if not exists.
      - When C(absent), the namespace will be removed.
      - When C(online), the namespace will be created if not exists and will be put in online state.
      - When C(offline), the namespace will be created if not exists and will be put in offline state.
      - When C(online)/C(offline) only state of namespace will be set, not the state of targets.
    choices:
      - present
      - absent
      - online
      - offline
    default: present
  access_based_enumeration:
    description:
      - Indicates whether a DFS namespace uses access-based enumeration.
      - If this value is C(yes), a DFS namespace server shows a user only the files and folders that the user can access.
    type: bool
    default: false
  insite_referrals:
    description:
      - Indicates whether a DFS namespace server provides a client only with referrals that are in the same site as the client.
      - If this value is C(yes), the DFS namespace server provides only in-site referrals.
      - If this value is C(no), the DFS namespace server provides in-site referrals first, then other referrals.
    type: bool
    default: false
  root_scalability:
    description:
      - Indicates whether a DFS namespace uses root scalability mode.
      - If this value is C(yes), DFS namespace servers connect to the nearest domain controllers for periodic namespace updates.
      - If this value is C(no), the servers connect to the primary domain controller (PDC) emulator.
    type: bool
    default: false
  site_costing:
    description:
      - Indicates whether a DFS namespace uses cost-based selection.
      - If a client cannot access a folder target in-site, a DFS namespace server selects the least resource intensive alternative.
      - If you provide a value of C(yes) for this parameter, DFS namespace favors high-speed links over wide area network (WAN) links.
    type: bool
    default: false
  target_failback:
    description:
      - Indicates whether a DFS namespace uses target failback.
      - If a client attempts to access a target on a server and that server is not available, the client fails over to another referral.
      - If this value is C(yes), once the first server becomes available again, the client fails back to the first server.
      - If this value is C(no), the DFS namespace server does not require the client to fail back to the preferred server.
    type: bool
    default: false
  ttl:
    description:
      - TTL interval, in seconds, for referrals. Clients store referrals to root targets for this length of time.
    type: int
    default: 300

seealso:
- module: win_share
- module: win_dfs_namespace_folder
- module: win_dfs_replication_group

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
- name: Create DFS namespace with SiteCosting option
  win_dfs_namespace_root:
    path: '\\domain.exmaple.com\dfs'
    targets:
      - '\\dc1.domain.exmaple.com\dfs'
      - '\\dc2.domain.exmaple.com\dfs'
      - '\\dc3.domain.exmaple.com\dfs'
    type: "DomainV2"
    description: "DFS Namespace"
    site_costing: true
    state: present

- name: Remove DFS namespace
  win_dfs_namespace_root:
    path: '\\domain.exmaple.com\dfs'
    state: absent
'''