---
title: [转]Ceph PG Inconsistent Error处理
date: 2018-12-29 09:47:19
categories: ceph
tags: ceph

---
# 问题描述
ceph集群状态为HEALTH_ERR，ceph -s显示有pg状态不一致，ceph health detail输出如下：
```
# ceph health detail
HEALTH_ERR 2 pgs inconsistent; 1 pgs repair; 8 scrub errors
pg 14.16a is active+clean+scrubbing+deep+inconsistent+repair, acting [1,27,16]
pg 15.118 is active+clean+inconsistent, acting [0,15,27]
8 scrub errors
```
# 分析 & 解决
手动执行pg修复
ceph pg repair 14.16a
ceph pg deep-scrub 14.16a
结果：集群状态依旧HEALTH_ERR

重启对应osd daemon
systemctl restart ceph-osd@<osdid>.service
结果：集群状态依旧HEALTH_ERR

检查ceph-osd log
```
# vim ceph-osd.1.log-xxx.gz
...
2017-05-31 02:30:14.166348 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56a14fcc:::10000002380.0000061d:head candidate had a read error
2017-05-31 02:30:14.166358 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56a7ab13:::10000002380.00000446:head candidate had a read error
2017-05-31 02:30:14.166361 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56b34a7a:::10000002356.00000218:head candidate had a read error
2017-05-31 02:30:14.166363 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56c557e8:::10000002380.0000007a:head candidate had a read error
2017-05-31 02:30:14.166366 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56c8ceeb:::10000002380.00000854:head candidate had a read error
2017-05-31 02:30:14.166372 7f7aeefff700 -1 log_channel(cluster) log [ERR] : 14.16a shard 27: soid 14:56f50799:::1000000237c.0000019a:head candidate had a read error
2017-05-31 02:30:14.168485 7f7acebff700 -1 log_channel(cluster) log [ERR] : 14.16a deep-scrub 0 missing, 6 inconsistent objects
2017-05-31 02:30:14.168499 7f7acebff700 -1 log_channel(cluster) log [ERR] : 14.16a deep-scrub 6 errors
```
上面可以看出pg 14.16a里有几个objects报告candidate had a read error

查看出错的object的md5值
```
# md5sum /var/lib/ceph/osd/ceph-1/current/14.16a_head/10000002380.0000061d__head_33F2856A__e
dc191d3144c49077952ed059425d68b1  /var/lib/ceph/osd/ceph-1/current/14.16a_head/10000002380.0000061d__head_33F2856A__e

# md5sum /var/lib/ceph/osd/ceph-16/current/14.16a_head/10000002380.0000061d__head_33F2856A__e
dc191d3144c49077952ed059425d68b1  /var/lib/ceph/osd/ceph-16/current/14.16a_head/10000002380.0000061d__head_33F2856A__e

# md5sum /var/lib/ceph/osd/ceph-27/current/14.16a_head/10000002380.0000061d__head_33F2856A__e
md5sum: /var/lib/ceph/osd/ceph-27/current/14.16a_head/10000002380.0000061d__head_33F2856A__e: Input/output error
```
上面得出ceph-27上的object获取md5值失败，报Input/output error，这里猜测其对应的磁盘有问题；
查看ceph-27上pg 14.16a里别的object的md5值，输出正常，则证明磁盘还能工作，可能是文件有损坏，也可能磁盘上有部分坏道；

删除md5sum报IO错误的文件，然后执行ceph pg repair 14.16a，pg状态恢复正常；

磁盘检查与恢复
那磁盘是否有问题呢？执行以下步骤来检测并恢复：
```
# systemctl stop ceph-osd@27.service
# umount /dev/sdi1

# badblocks -svn /dev/sdi1 -o badblocks.log
Checking for bad blocks in non-destructive read-write mode
From block 0 to 3906984774
Checking for bad blocks (non-destructive read-write test)
Testing with random pattern: 0.00% done, 16:22 elapsed. (223/0/0 errors)
```
上述检查会花费比较长时间，一般SATA盘的read速度为100-120MB/s，4TB大小的SATA盘，约需要4*1024*1024/120/3600 = 9.7小时；

不过你可以在别的窗口查看输出文件badblocks.log的内容，如果里面有信息，那证明你的磁盘确实有坏块，就需要尝试恢复检查了:
```
# head -n 10 badblocks.log
10624
10625
10626
10627
10628
10629
10630
10631
10632
10633

kill badblocks检查进程
# ps aux | pgrep badblocks | xargs kill -9
[1]+  Killed                  badblocks -v /dev/sdi1 > badblocks
```

通过badblocks修复坏块，注意会丢失坏块里的数据
```
# badblocks -ws /dev/sdi1 10633 10624
Testing with pattern 0xaa: done
Reading and comparing: done
Testing with pattern 0x55: done
Reading and comparing: done
Testing with pattern 0xff: done
Reading and comparing: done
Testing with pattern 0x00: done
Reading and comparing: done

# badblocks -svn /dev/sdi1 10633 10624
Checking for bad blocks in non-destructive read-write mode
From block 10624 to 10633
Checking for bad blocks (non-destructive read-write test)
Testing with random pattern: done
Pass completed, 0 bad blocks found. (0/0/0 errors)
```
通过上述步骤恢复了磁盘中的坏块，有如下两种情况：

坏块中有xfs的元数据信息
执行xfs_repair修复磁盘上的xfs系统，很可能报错；
没有办法，只能重新格式化磁盘，然后执行ceph的recovery了；

坏块中无xfs的元数据信息
通过xfs_repair修复磁盘上的xfs系统，报告done
```
# xfs_repair  -f /dev/sdi1
Phase 1 - find and verify superblock...
Cannot get host filesystem geometry.
Repair may fail if there is a sector size mismatch between
the image and the host filesystem.
        - reporting progress in intervals of 15 minutes
Phase 2 - using internal log
        - zero log...
        - scan filesystem freespace and inode maps...
        - 15:23:37: scanning filesystem freespace - 32 of 32 allocation groups done
        - found root inode chunk
Phase 3 - for each AG...
        - scan and clear agi unlinked lists...
        - 15:23:37: scanning agi unlinked lists - 32 of 32 allocation groups done
        - process known inodes and perform inode discovery...
...
        - 15:23:42: process known inodes and inode discovery - 3584 of 3584 inodes done
        - process newly discovered inodes...
        - 15:23:42: process newly discovered inodes - 32 of 32 allocation groups done
Phase 4 - check for duplicate blocks...
        - setting up duplicate extent list...
        - 15:23:42: setting up duplicate extent list - 32 of 32 allocation groups done
        - check for inodes claiming duplicate blocks...
...
        - 15:23:42: check for inodes claiming duplicate blocks - 3584 of 3584 inodes done
Phase 5 - rebuild AG headers and trees...
        - 15:23:42: rebuild AG headers and trees - 32 of 32 allocation groups done
        - reset superblock...
Phase 6 - check inode connectivity...
        - resetting contents of realtime bitmap and summary inodes
        - traversing filesystem ...
        - traversal finished ...
        - moving disconnected inodes to lost+found ...
Phase 7 - verify and correct link counts...
done
```
这时mount，start ceph-osd damon后，ceph报HEALTH_OK，但其实osd上的部分数据已经丢失，这个等ceph的deep scrub触发后会自动修复；

# 参考
http://ceph.com/planet/ceph-manually-repair-object/
https://linux.cn/article-7961-1.html

