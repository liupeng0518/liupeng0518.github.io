---
title: tmpfs
date: 2018-06-28 10:10:39
categories: 运维
tags: [, linux]
---

# 什么是tmpfs

tpmfs相关内容



## 我们用df命令看到的 /run/user/1000 的tmpfs是什么？

```bash
tmpfs                             49M     0   49M   0% /run/user/0
tmpfs                             49M     0   49M   0% /run/user/1000
```
我们来看红帽的解释：

[What is the purpose of the /run/user/1000, tmpfs filesystem that appears in df?](https://access.redhat.com/solutions/2060373)

### 问题：

We could see /run/user/1000 filesystem , is this a symptom of any issue?
Why do I see multiple of tmpfs filesystems / partitions in the output of df?
Why do I see a /run/user/$UID directory when the user is not logged in (i.e. does not appear in the output of w or who)?

### 决议：

The directory `/run/user/$UID` is used by `pam_systemd` to store files that previously where put in `/tmp`.
This is normal and should not cause any issues.
**NOTE**: since `systemd-219.19`, /run/user/$UID is mounted as tmpfs.

The manual page of `pam_systemd(8)` gives more indications on this.

```bash
# man pam_systemd
```

### 根源：

From the pam_systemd(8) manual page:

pam_systemd registers user sessions with the systemd login manager systemd-logind.service(8), and hence the systemd control group hierarchy.

On login, this module ensures the following:

1. If it does not exist yet, the user runtime directory /run/user/\$USER is created and its ownership changed to the user that is logging in. Then, /run/user/$USER is mounted as tmpfs.

2. The $XDG_SESSION_ID environment variable is initialized. If auditing is available and pam_loginuid.so was run before this module (which is highly recommended), the variable is
initialized from the auditing session id (/proc/self/sessionid). Otherwise, an independent session counter is used.

3. A new systemd scope unit is created for the session. If this is the first concurrent session of the user, an implicit slice below user.slice is automatically created and the
scope placed into it.

On logout, this module ensures the following:

1. If enabled in logind.conf(5), all processes of the session are terminated. If the last concurrent session of a user ends, the user's slice unit will be terminated too.

2. If the last concurrent session of a user ends, the \$XDG_RUNTIME_DIR directory and all its contents are removed, too. Then, /run/user/$USER is unmounted.

If the system was not booted up with systemd as init system, this module does nothing and immediately returns PAM_SUCCESS.

### 诊断步骤：

The logged in users (a.k.a. users with active logind sessions) can be see with the `loginctl` command.


```bash
[root@node2 ~]# loginctl 
   SESSION        UID USER             SEAT            
         6       1000 george                           
         7          0 root                             

2 sessions listed.

[root@node2 ~]# mount | grep user
tmpfs on /run/user/1000 type tmpfs (rw,nosuid,nodev,relatime,size=1190072k,mode=700,uid=1000,gid=1000)
gvfsd-fuse on /run/user/1000/gvfs type fuse.gvfsd-fuse (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)
tmpfs on /run/user/0 type tmpfs (rw,nosuid,nodev,relatime,size=1190072k,mode=700)

[root@node2 ~]# df | grep user
tmpfs                   1190072        52   1190020   1% /run/user/1000
tmpfs                   1190072         0   1190072   0% /run/user/0
```

Again with the `loginctl` command we can see some more details about any user with an active session. This can help identify *why* the user has an active session (i.e. what processes is the user running).


```bash
[root@node2 ~]# loginctl user-status 1000
george (1000)
           Since: Wed 2016-04-20 09:39:38 CEST; 1min 45s ago
           State: active
        Sessions: *6
            Unit: user-1000.slice
                  └─session-6.scope
                    ├─6868 sshd: george [priv] 
                    ├─6874 sshd: george@pts/0  
                    └─6875 -bash

Apr 20 09:39:38 node2 systemd[1]: Starting user-1000.slice.
Apr 20 09:39:38 node2 sshd[6868]: pam_unix(sshd:session): session opened for user george by (uid=0)

[root@node2 ~]# loginctl show-user george
UID=1000
GID=1000
Name=george
Timestamp=Wed 2016-04-20 09:39:38 CEST
TimestampMonotonic=925489438
RuntimePath=/run/user/1000
Slice=user-1000.slice
Display=6
State=active
Sessions=6
IdleHint=no
IdleSinceHint=0
IdleSinceHintMonotonic=0
Linger=no
```

Traditionally the `w` and `who` commands have been used to check which users are logged in. However, in RHEL7, `loginctl` has more reliable data. For example, if a user is connected through `sftp`, they do not have an terminal connection (no `tty` or `pty/pts`). Because of this, the user does not appear in `w` or `who`, but they do appear in `loginctl` and they have a `/run/user/$UID` directory and an active session. Again, this can be checked with the `loginctl` commands shown above.

[systemd-208-20/src/login-user.c]

```
static int user_mkdir_runtime_path(User *u) {                                                            
        char *p;                                                                                         
        int r;                                                                                           

        assert(u);                                                                                       

        r = mkdir_safe_label("/run/user", 0755, 0, 0);                                                   
        if (r < 0) {
                log_error("Failed to create /run/user: %s", strerror(-r));                               
                return r;                                                                                
        }                                                                                                

        if (!u->runtime_path) {
                if (asprintf(&p, "/run/user/%lu", (unsigned long) u->uid) < 0)                           
                        return log_oom();                                                                
        } else  
                p = u->runtime_path;                                                                     

        r = mkdir_safe_label(p, 0700, u->uid, u->gid);                                                   
        if (r < 0) {
                log_error("Failed to create runtime directory %s: %s", p, strerror(-r));                 
                free(p);
                u->runtime_path = NULL;                                                                  
                return r;                                                                                
        }                                                                                                

        u->runtime_path = p;                                                                             
        return 0;                                                                                        
}       
```

[systemd-219.19/src/login-user.c]

```
static int user_mkdir_runtime_path(User *u) {
        char *p;
        int r;

        assert(u);

        r = mkdir_safe_label("/run/user", 0755, 0, 0);
        if (r < 0)
                return log_error_errno(r, "Failed to create /run/user: %m");

        if (!u->runtime_path) {
                if (asprintf(&p, "/run/user/" UID_FMT, u->uid) < 0)
                        return log_oom();
        } else
                p = u->runtime_path;

        if (path_is_mount_point(p, false) <= 0) {
                _cleanup_free_ char *t = NULL;

                (void) mkdir(p, 0700);

                if (mac_smack_use())
                        r = asprintf(&t, "mode=0700,smackfsroot=*,uid=" UID_FMT ",gid=" GID_FMT ",size=%zu", u->uid, u->gid, u->manager->runtime_dir_size);
                else
                        r = asprintf(&t, "mode=0700,uid=" UID_FMT ",gid=" GID_FMT ",size=%zu", u->uid, u->gid, u->manager->runtime_dir_size);
                if (r < 0) {
                        r = log_oom();
                        goto fail;
                }

                r = mount("tmpfs", p, "tmpfs", MS_NODEV|MS_NOSUID, t);
                if (r < 0) {
                        if (errno != EPERM) {
                                r = log_error_errno(errno, "Failed to mount per-user tmpfs directory %s: %m", p);
                                goto fail;
                        }

                        /* Lacking permissions, maybe
                         * CAP_SYS_ADMIN-less container? In this case,
                         * just use a normal directory. */

                        r = chmod_and_chown(p, 0700, u->uid, u->gid);
                        if (r < 0) {
                                log_error_errno(r, "Failed to change runtime directory ownership and mode: %m");
                                goto fail;
                        }
                }
        }

        u->runtime_path = p;
        return 0;

fail:
        if (p) {
                /* Try to clean up, but ignore errors */
                (void) rmdir(p);
                free(p);
        }

        u->runtime_path = NULL;
        return r;
}
```

 



# devtmpfs
# shm



## 参考连接

https://unix.stackexchange.com/questions/162900/what-is-this-folder-run-user-1000