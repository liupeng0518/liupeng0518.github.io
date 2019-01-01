---
title: ceph_pool管理
date: 2018-12-29 09:47:19
categories: ceph
tags: [ceph, pool]

---

# 目标
ceph 下利用命令行对池管理

# 显示池
> 参考下面命令可以查询当前 ceph 中 pool 信息

```
[root@cephsvr-128040 ceph]# rados lspools
volumes
[root@cephsvr-128040 ceph]# ceph osd lspools
1 volumes,
[root@cephsvr-128040 ceph]# ceph osd pool ls
volumes
[root@cephsvr-128040 ceph]# ceph osd pool ls detail
pool 1 'volumes' replicated size 3 min_size 1 crush_rule 0 object_hash rjenkins pg_num 2048 pgp_num 2048 last_change 161 flags hashpspool stripe_width 0 application rbd
                removed_snaps [1~3]
```
# 池使用率
参考下面命令
```
[root@cephsvr-128040 ceph]# rados df
POOL_NAME USED  OBJECTS CLONES COPIES MISSING_ON_PRIMARY UNFOUND DEGRADED RD_OPS RD    WR_OPS WR
volumes   1496M     383      0   1149                  0       0        0  42762 1528M   2422 1485M

total_objects    383
total_used       8476M
total_avail      196T
total_space      196T
```
>
```
[root@cephsvr-128040 ceph]# ceph df
GLOBAL:
        SIZE     AVAIL     RAW USED     %RAW USED
        196T      196T        8476M             0
POOLS:
        NAME        ID     USED      %USED     MAX AVAIL     OBJECTS
        volumes     1      1496M         0          186T         383
```
# 创建池
格式
```
ceph osd pool create {pool-name} {pg-num} [{pgp-num}]
```
命令行
```
ceph osd pool create volumes 2048 2048 
```

## pg-num 与 gpg-num

>
>当前以 36 osd 只创建一个池 3 副本的容量进行计算 
假如预计以后需要进行两倍扩容, 那么建议 pg-num 与 pgp-num 设定为 4096 
pg-num 与 pgp-num 只可以扩大不可以缩小 
pg-num 与 pgp-num 常见数量一样 
建议在创建池时候就定义好合理的 pg-num 与 pgp-num 
在改变(增加) pg-num 与 pgp-num 时候, 会自动产生 rebalance 操作, 会严重影响 ceph cluster io 性能



[参考官方推荐 OSD 计算方法](http://ceph.com/pgcalc/)

### 查询 pg pgp
```
[root@cephsvr-128040 ceph]# ceph osd pool get volumes pg_num
pg_num: 2048
[root@cephsvr-128040 ceph]# ceph osd pool get volumes pgp_num
pgp_num: 2048
```

### 修改
```
[root@cephsvr-128040 ceph]# ceph osd pool set volumes pg_num 3000
set pool 1 pg_num to 3000
[root@cephsvr-128040 ceph]# ceph osd pool set volumes pgp_num 3000
set pool 1 pgp_num to 3000
```
述只作为修改例子 
常见 pg-num 与 pgp-num 都为 2 的平方数倍数

## pool size
pool size 用于指定当前存放在对应池中的文件实际保存的文件副本数量, 常见为 3

### 查询
```
[root@cephsvr-128040 ceph]# ceph osd pool get volumes size
size: 3
```
### 修改
```
[root@cephsvr-128040 ceph]# ceph osd pool set volumes size 3
set pool 1 size to 3
```
## pool rule
rule 修改, 格式参考 crush map 说明

### 查询
```
[root@cephsvr-128040 ~]# ceph osd dump | grep "^pool" | grep "crush"
pool 2 'volumes' replicated size 3 min_size 1 crush_rule 0 object_hash rjenkins pg_num 2048 pgp_num 2048 last_change 244 flags hashpspool stripe_width 0 application rbd
```
另外一种方法
```
[root@cephsvr-128040 tmp]# ceph osd pool get volumes crush_rule
crush_rule: replicated_rule
```
# 定义池使用类型
这个是 luminous 版本新特性 
在不定义池使用类型时, 会获得下面错误信息
```
[root@cephsvr-128040 ~]# ceph -s
    cluster:
        id:     c45b752d-5d4d-4d3a-a3b2-04e73eff4ccd
        health: HEALTH_WARN
                        application not enabled on 1 pool(s)       <- 参考这里
                        too many PGs per OSD (341 > max 300)

    services:
        mon: 3 daemons, quorum cephsvr-128040,cephsvr-128214,cephsvr-128215
        mgr: openstack(active)
        osd: 36 osds: 36 up, 36 in

    data:
        pools:   2 pools, 4096 pgs
        objects: 10343 objects, 33214 MB
        usage:   101 GB used, 196 TB / 196 TB avail
        pgs:     4096 active+clean
```
# 设定池类型
```
[root@cephsvr-128040 tmp]# ceph osd pool application enable volumes rbd
enabled application 'rbd' on pool 'volumes'
```
当前常见池使用类型有三种
>
>CephFS uses the application name cephfs 
>RBD uses the application name rbd 
>RGW uses the application name rgw
>

修改方法
```
[root@cephsvr-128040 ~]# ceph osd dump | grep "^pool" | grep "crush"
pool 1 'volumes' replicated size 3 min_size 1 crush_rule 0 object_hash rjenkins pg_num 2048 pgp_num 2048 last_change 506 flags hashpspool stripe_width 0
[root@cephsvr-128040 ~]#  ceph osd pool application enable data rbd
enabled application 'rbd' on pool 'data'
[root@cephsvr-128040 ~]# ceph osd dump | grep "^pool" | grep "crush"
pool 1 'volumes' replicated size 3 min_size 1 crush_rule 0 object_hash rjenkins pg_num 2048 pgp_num 2048 last_change 532 flags hashpspool stripe_width 0 application rbd
```
# 初始化 rbd 池
这个是 luminous 版本新特性
```
[root@cephsvr-128040 tmp]# rbd pool init volumes
```
# rbd 文件导入
```
[root@cephsvr-128040 tmp]# rbd -p volumes import 7.tar 8.tar
rbd: --pool is deprecated for import, use --dest-pool
Importing image: 100% complete...done.
[root@cephsvr-128040 tmp]# rbd --dest-pool volumes import 7.tar 9.tar
Importing image: 100% complete...done.
```
注意

-p 参数已经弃用, 需要使用 –dest-pool 参数

# rbd 文件导出
```
[root@cephsvr-128040 tmp]# rbd -p volumes export 8.tar 8.tar
Exporting image: 100% complete...done.
```
# 删除池
当执行删除操作, 池中所有数据都会清空 
注意下面错误信息
```
[root@cephsvr-128040 ceph]# ceph osd pool delete volumes volumes --yes-i-really-really-mean-it
Error EPERM: pool deletion is disabled; you must first set the mon_allow_pool_delete config option to true before you can destroy a pool
```
以上是 luminous 版本的新特性 
你需要配置 mon_allow_pool_delete 配置后才允许对 pool 进行删除

## 查询配置
```
[root@cephsvr-128040 ceph]# ceph --admin-daemon /var/run/ceph/ceph-osd.0.asok config show | grep mon_allow_pool_delete
        "mon_allow_pool_delete": "false",
```
## 修改配置
### 获得ceph mon socket 位置
```
[root@cephsvr-128040 tmp]# ceph-conf --name mon.$(hostname -s) --show-config-value admin_socket
/var/run/ceph/ceph-mon.cephsvr-128040.asok
```
### 显示 mon 配置
```
[root@cephsvr-128040 tmp]# ceph daemon /var/run/ceph/ceph-mon.$(hostname -s).asok config show | grep mon_allow_pool_delete
        "mon_allow_pool_delete": "false",
```
### 修改配置
```
[root@cephsvr-128040 ceph]# ceph osd pool delete volumes volumes --yes-i-really-really-mean-it
Error EPERM: pool deletion is disabled; you must first set the mon_allow_pool_delete config option to true before you can destroy a pool


[root@cephsvr-128040 tmp]# ceph daemon /var/run/ceph/ceph-mon.$(hostname -s).asok config show | grep mon_allow_pool_delete
        "mon_allow_pool_delete": "false",

[root@cephsvr-128040 tmp]# ceph tell mon.cephsvr-128040 injectargs '--mon_allow_pool_delete=true'
injectargs:mon_allow_pool_delete = 'true' (not observed, change may require restart)
```
请忽略这里的 [not observed, change may require restart] 告警
```
[root@cephsvr-128040 tmp]# ceph daemon /var/run/ceph/ceph-mon.$(hostname -s).asok config show | grep mon_allow_pool_delete
        "mon_allow_pool_delete": "true",

[root@cephsvr-128040 ceph]# ceph osd pool delete volumes volumes --yes-i-really-really-mean-it
pool 'volumes' removed
```


原文：https://blog.csdn.net/signmem/article/details/78594340 
