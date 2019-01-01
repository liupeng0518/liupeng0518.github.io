---
title: ceph_rbd管理
date: 2018-12-29 09:47:19
categories: ceph
tags: [ceph, rbd]

---

创建块设备映像
```
rbd create --size {megabytes} {pool-name}/{image-name}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ rbd create --size 1024 foo
```
罗列块设备映像
```
rbd ls {poolname}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ rbd ls # rbd list
foo
```
检索映像信息
```
rbd info {pool-name}/{image-name}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ rbd info foo
rbd image 'foo':
    size 1024 MB in 256 objects
    order 22 (4096 kB objects)
    block_name_prefix: rbd_data.d3a4238e1f29
    format: 2
    features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
    flags: 
```
调整块设备映像大小
```
rbd resize --size 2048 foo (to increase)
rbd resize --size 2048 foo --allow-shrink (to decrease)
```

实例：
```
[ceph-deploy@ceph-admin ~]$ rbd resize --size 2048 foo
Resizing image: 100% complete...done.
[ceph-deploy@ceph-admin ~]$ rbd info foo
rbd image 'foo':
    size 2048 MB in 512 objects
    order 22 (4096 kB objects)
    block_name_prefix: rbd_data.d3a4238e1f29
    format: 2
    features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
    flags: 
```
删除块设备映像
```
rbd rm {pool-name}/{image-name}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ rbd rm foo
Removing image: 100% complete...done.
```
映射块设备
```
sudo rbd map {pool-name}/{image-name} --id {user-name}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ sudo rbd map rbd/foo 1
/dev/rbd0
```

查看已映射块设备
```
rbd showmapped
```
实例：
```
[ceph-deploy@ceph-admin ~]$ rbd showmapped
id pool image snap device    
0  rbd  foo   -    /dev/rbd0 
```
取消块设备映射
```
sudo rbd unmap /dev/rbd/{poolname}/{imagename}
```
实例：
```
[ceph-deploy@ceph-admin ~]$ sudo rbd unmap /dev/rbd0
```
使用Ceph块设备
创建并挂载一个文件系统：
```
[ceph-deploy@ceph-admin ~]$ sudo mkfs.xfs /dev/rbd0
meta-data=/dev/rbd0              isize=512    agcount=9, agsize=64512 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=524288, imaxpct=25
         =                       sunit=1024   swidth=1024 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=8 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[ceph-deploy@ceph-admin ~]$ sudo mkdir /mnt/ceph-disk0
[ceph-deploy@ceph-admin ~]$ sudo mount /dev/rbd0 /mnt/ceph-disk0
[ceph-deploy@ceph-admin ~]$ df -h /mnt/ceph-disk0
Filesystem                 Size  Used Avail Use% Mounted on
/dev/rbd0                  2.0G   33M  2.0G   2% /mnt/ceph-disk0
```
通过将数据写入块设备来进行检测：
```
[ceph-deploy@ceph-admin ~]$ sudo dd if=/dev/zero of=/mnt/ceph-disk0/file0 count=100 bs=1M
100+0 records in
100+0 records out
104857600 bytes (105 MB) copied, 0.779733 s, 134 MB/s
[ceph-deploy@ceph-admin ~]$ sudo ls /mnt/ceph-disk0/file0 -lh
-rw-r--r--. 1 root root 100M Jul 19 15:33 /mnt/ceph-disk0/file0
[ceph-deploy@ceph-admin ~]$ df -h /mnt/ceph-disk0
Filesystem                 Size  Used Avail Use% Mounted on
/dev/rbd0                  2.0G  133M  1.9G   7% /mnt/ceph-disk0
```
增加块设备映像大小后，扩展文件系统来利用增加了的存储空间
```
[ceph-deploy@ceph-admin ~]$ sudo dmesg | grep -i capacity
[17945.781304] rbd: rbd0: capacity 2147483648 features 0x1
[21955.926051] rbd0: detected capacity change from 2147483648 to 4294967296
[ceph-deploy@ceph-admin ~]$ sudo xfs_growfs -d /mnt/ceph-disk0/
meta-data=/dev/rbd0              isize=512    agcount=9, agsize=64512 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0 spinodes=0
data     =                       bsize=4096   blocks=524288, imaxpct=25
         =                       sunit=1024   swidth=1024 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal               bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=8 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
data blocks changed from 524288 to 1048576
[ceph-deploy@ceph-admin ~]$ df -h /mnt/ceph-disk0
Filesystem                 Size  Used Avail Use% Mounted on
/dev/rbd0                  4.0G  133M  3.9G   4% /mnt/ceph-disk0
```
可能遇到的错误：
```
[ceph-deploy@ceph-admin ~]$ sudo rbd map rbd/foo 
rbd: sysfs write failed
RBD image feature set mismatch. You can disable features unsupported by the kernel with "rbd feature disable".
In some cases useful info is found in syslog - try "dmesg | tail" or so.
rbd: map failed: (6) No such device or address
```
原因：
rbd镜像的一些特性，OS kernel并不支持，所以映射失败。

查看该镜像支持了哪些特性：
```
[ceph-deploy@ceph-admin ~]$ rbd info foo
rbd image 'foo':
    size 2048 MB in 512 objects
    order 22 (4096 kB objects)
    block_name_prefix: rbd_data.d3a4238e1f29
    format: 2
    features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
    flags: 
```
可以看到特性feature一栏，由于OS的kernel只支持layering，其他都不支持，所以需要把部分不支持的特性disable掉。

解决方案一：
直接diable这个rbd镜像的不支持的特性：
```
[ceph-deploy@ceph-admin ~]$ rbd feature disable foo exclusive-lock object-map fast-diff deep-flatten
```
解决方案二：
创建rbd镜像时就指明需要的特性，如：
```
[ceph-deploy@ceph-admin ~]$ rbd create --size 2048 foo --image-feature layering
```
解决方案三：
如果还想一劳永逸，那么就在执行创建rbd镜像命令的服务器中，修改Ceph配置文件/etc/ceph/ceph.conf，在global section下，增加 
rbd_default_features = 1，再创建rdb镜像：
```
[ceph-deploy@ceph-admin ~]$ rbd create --size 2048 foo
```
通过上述三种方法后，查看rbd镜像的信息
```
[ceph-deploy@ceph-admin ~]$ rbd info foo
rbd image 'foo':
    size 2048 MB in 512 objects
    order 22 (4096 kB objects)
    block_name_prefix: rbd_data.d3a4238e1f29
    format: 2
    features: layering
    flags: 
```
再次尝试映射rdb镜像到本地块设备，成功！
```
[ceph-deploy@ceph-admin ~]$ sudo rbd map rbd/foo 
/dev/rbd0
```

原文：https://blog.csdn.net/JDPlus/article/details/75561537 
