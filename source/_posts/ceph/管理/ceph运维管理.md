---
title: ceph运维管理
date: 2018-12-29 09:47:19
categories: ceph
tags: ceph

---
# 开启监控模块
在配置文件/etc/ceph/ceph.conf中添加
```
[mgr]
mgr modules = dashboard
```
或者
```
ceph mgr module enable dashboard
```
设置dashboard的ip和端口
```
ceph config-key put mgr/dashboard/server_addr 10.7.12.201
ceph config-key put mgr/dashboard/server_port 7000
```
或
ceph config-key put mgr/dashboard/server_addr ::

重启mgr服务
```
systemctl restart ceph-mgr@
```

参考：https://blog.widodh.nl/2017/06/using-the-new-dashboard-in-ceph-mgr/

# 