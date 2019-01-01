---
title: ceph-ansible部署
date: 2018-12-29 09:47:19
categories: ceph
tags: [ceph, ansible]

---
ceph-ansible 官方出品，极大简化工作效率。
这里简单列出部署一个测试集群。

### 环境说明

| hostname | ip | role | os |
| --- | --- | --- | --- |
| k8s-m1 | 10.7.12.201 | mon/osd/mgr | CentOS Linux release 7.6.1810 (Core)  |
| k8s-m2 | 10.7.12.202 | mon/osd/mgr | CentOS Linux release 7.6.1810 (Core)  |
| k8s-m3 | 10.7.12.203 | mon/osd/mgr | CentOS Linux release 7.6.1810 (Core)  |

> 
> 
> 内核升级为 4.18.16-1.el7.elrepo.x86_64
> 
> 

### 部署环境安装
这里我们打算使用版本3.2 的部署，这里要求ansible的版本最高不能超过2.6
```
yum -y install epel-release
yum -y install python-pip
pip install ansible=2.6.11

```


### 安装

#### 下载项目

```
git clone https://github.com/ceph/ceph-ansible.git
cd ceph-ansible/
git checkout v3.2.0
# 依赖安装
pip install -r requirements.txt

```

#### host

```
[mons]
10.7.12.201
10.7.12.202
10.7.12.203

[osds]
10.7.12.201
10.7.12.202
10.7.12.203

[mgrs]
10.7.12.201
10.7.12.202
10.7.12.203

[mdss]
10.7.12.201
10.7.12.202
10.7.12.203

[clients]
10.7.12.201
10.7.12.202
10.7.12.203
10.7.12.204
10.7.12.205


```

#### 修改配置

group_vars/all.yml
```

cp group_vars/all.yml.sample group_vars/all.yml

vim group_vars/all.yml

ceph_origin: repository
ceph_repository: community
ceph_mirror: http://mirrors.aliyun.com/ceph
ceph_stable_key: http://mirrors.aliyun.com/ceph/keys/release.asc
ceph_stable_release: luminous
ceph_stable_repo: "{{ ceph_mirror }}/rpm-{{ ceph_stable_release }}"

fsid: 54d55c64-d458-4208-9592-36ce881cbcb7 ##通过uuidgen生成
generate_fsid: false

cephx: true

public_network: 10.7.12.0/16
cluster_network: 10.7.12.0/16
monitor_interface: eth0

ceph_conf_overrides:
    global:
      rbd_default_features: 7
      auth cluster required: cephx
      auth service required: cephx
      auth client required: cephx
      osd journal size: 2048
      osd pool default size: 3
      osd pool default min size: 1
      mon_pg_warn_max_per_osd: 1024
      osd pool default pg num: 128
      osd pool default pgp num: 128
      max open files: 131072
      osd_deep_scrub_randomize_ratio: 0.01

    mgr:
      mgr modules: dashboard

    mon:
      mon_allow_pool_delete: true

    client:
      rbd_cache: true
      rbd_cache_size: 335544320
      rbd_cache_max_dirty: 134217728
      rbd_cache_max_dirty_age: 10

    osd:
      osd mkfs type: xfs
      osd mount options xfs: "rw,noexec,nodev,noatime,nodiratime,nobarrier"
      ms_bind_port_max: 7100
      osd_client_message_size_cap: 2147483648
      osd_crush_update_on_start: true
      osd_deep_scrub_stride: 131072
      osd_disk_threads: 4
      osd_map_cache_bl_size: 128
      osd_max_object_name_len: 256
      osd_max_object_namespace_len: 64
      osd_max_write_size: 1024
      osd_op_threads: 8

      osd_recovery_op_priority: 1
      osd_recovery_max_active: 1
      osd_recovery_max_single_start: 1
      osd_recovery_max_chunk: 1048576
      osd_recovery_threads: 1
      osd_max_backfills: 4
      osd_scrub_begin_hour: 23
      osd_scrub_end_hour: 7

     # bluestore block create: true
     # bluestore block db size: 73014444032
     # bluestore block db create: true
     # bluestore block wal size: 107374182400
     # bluestore block wal create: true

```
groups_vars/osds.yml
```
cp group_vars/osds.yml.sample group_vars/osds.yml

vim group_vars/osds.yml
devices:
  - /dev/vdb
  - /dev/vdc
  - /dev/vdd
  - /dev/vde
osd_scenario: collocated
osd_objectstore: bluestore

#osd_scenario: non-collocated
#osd_objectstore: bluestore
#devices:
#  - /dev/sdc
#  - /dev/sdd
#  - /dev/sde
#dedicated_devices:
#  - /dev/sdf
#  - /dev/sdf
#  - /dev/sdf
#bluestore_wal_devices:
#  - /dev/sdg
#  - /dev/sdg
#  - /dev/sdg
#
#monitor_address: 192.168.66.125
```

site.yml
```
cp site.yml.sample site.yml

# 选择需要部署的组件
vim site.yml
---
# Defines deployment design and assigns role to server groups

- hosts:
  - mons
#  - agents
  - osds
  - mdss
#  - rgws
#  - nfss
#  - restapis
#  - rbdmirrors
  - clients
  - mgrs
#  - iscsigws
#  - iscsi-gws # for backward compatibility only!


```
#### 部署

```
ansible-playbook -i hosts site.yml

```
如果顺利，至此ceph部署完成，登陆ceph节点检查状态。

#### 清空集群

```
cp infrastructure-playbooks/purge-cluster.yml purge-cluster.yml 
ansible-playbook -i hosts purge-cluster.yml

```

