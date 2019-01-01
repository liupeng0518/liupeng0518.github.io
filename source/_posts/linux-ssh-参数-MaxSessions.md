---
title: ssh 参数--MaxSessions
date: 2017-03-09 14:18:24
categories: 运维
tags: [ssh, linux]
---
# 问题描述
sshd相关配置文件解读之MaxSessions；
这个问题出现在生产环境中的问题，之后对这个参数进行解读，发现网上大部分理解错了或是模棱两可；
# 理解

man 中解释：
```bash
MaxSessions
Specifies the maximum number of open shell, login or subsystem (e.g. sftp) sessions permitted per network connection. Multiple sessions may be established by clients that support connection multiplexing. Setting MaxSessions to 1 will effectively disable session multiplexing, whereas setting it to 0 will prevent all shell, login and subsystem sessions while still permitting forwarding. The default is 10.
```
其实已经说的明白了就是：这在通过单个TCP连接复用ssh session时使用。并不是单个电脑或单个ip连接的数量。

例如，使用securecrt克隆会话时（右键克隆），原有会话连接的session数会自增。但是克隆出来的可以再继续克隆。
也就是从同一个会话克隆的最大数量（默认10），假如超过10个：
```bash
tail -f /var/log/secure
... ...
sshd[10134]: error: no more sessions
```
可见，新建会话，会消耗一个session计数，如果在当前会话中新建会话，就会继续消耗当前会话的会话数。假如消耗的会话大于设置的maxsessions，则会报错。
# 参考
https://en.wikibooks.org/wiki/OpenSSH
http://unix.stackexchange.com/questions/26170/sshd-config-maxsessions-parameter
https://yq.aliyun.com/articles/58404
/usr/src/debug/openssh-6.4p1/sessions.c
