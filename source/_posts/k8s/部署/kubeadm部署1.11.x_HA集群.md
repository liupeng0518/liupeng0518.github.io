---
title: kubeadm部署1.11.x_HA集群
date: 2018-12-24 09:47:19
categories: k8s
tags: [k8s, kubeadm]

---


# 1 实验环境说明
实验环境
lab1: etcd master haproxy keepalived 10.7.12.201
lab2: etcd master haproxy keepalived 10.7.12.202
lab3: etcd master haproxy keepalived 10.7.12.203
lab4: node  10.7.12.204

同时lab1-lab3 部署了ceph集群

vip(loadblancer ip): 10.7.12.200

# 2 基础环境配置

## 2.1 安装docker  

v1.11.x版本推荐使用docker v17.03,配置国内docker源（daocloud或者aliyun）：  
```
sudo yum install -y yum-utils
sudo yum-config-manager \
    --add-repo \
     https://download.daocloud.io/docker/linux/centos/docker-ce.repo
sudo yum install -y -q --setopt=obsoletes=0 docker-ce-17.03.2.ce* docker-ce-selinux-17.03.2.ce*
sudo systemctl enable docker
sudo systemctl start docker
sudo service docker status
```

## 2.2 配置国内 docker 镜像加速器  
```
# 加速镜像下载（或者配置aliyun）
curl -sSL https://get.daocloud.io/daotools/set_mirror.sh | sh -s http://xxx(个人账户).m.daocloud.io
```

## 2.3 安装 kube* (所有节点)

```
# 配置源,使用阿里镜像安装
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# 安装
yum install -y kubelet kubeadm kubectl ipvsadm
```
## 2.4 基础系统参数配置
```
# 关闭 selinux
sed -i 's/SELINUX=permissive/SELINUX=disabled/' /etc/sysconfig/selinux
setenforce 0

# 关闭swap
# 注释/etc/fstab文件里swap相关的行并执行:
swapoff -a
​
# 配置转发相关参数，否则可能会出错
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
vm.swappiness=0
EOF
sysctl --system

# 开启forward, Docker从1.13版本开始调整了默认的防火墙规则
# 禁用了iptables filter表中FOWARD链, 这样会导致Kubernetes集群中跨Node的Pod无法通信
iptables -P FORWARD ACCEPT

# 加载ipvs相关内核模块
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack_ipv4

lsmod | grep ip_vs

# 开机生效
cat >>/etc/rc.local<EOF
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack_ipv4
EOF

chmod +x /etc/rc.local

# 配置hosts解析

cat >>/etc/hosts<<EOF
10.7.12.201 lab1
10.7.12.202 lab2
10.7.12.203 lab3
10.7.12.204 lab4

EOF
```

# 3 高可用组件配置

配置haproxy和keepalived，这里我们选取了lab1-lab3三台机器，作为 haproxy+keepalived 集群， 为k8s集群提供vip服务（高可用服务），此章节需要在节点lab1,lab2,lab3操作
## 3.1 haproxy配置

### 拉取镜像并修改haproxy配置

```bash
# 拉取haproxy镜像
docker pull haproxy:1.7.8-alpine
mkdir /etc/haproxy
cat >/etc/haproxy/haproxy.cfg<<EOF
global
  log 127.0.0.1 local0 err
  maxconn 50000
  uid 99
  gid 99
  #daemon
  nbproc 1
  pidfile haproxy.pid

defaults
  mode http
  log 127.0.0.1 local0 err
  maxconn 50000
  retries 3
  timeout connect 5s
  timeout client 30s
  timeout server 30s
  timeout check 2s

listen admin_stats
  mode http
  bind 0.0.0.0:1080
  log 127.0.0.1 local0 err
  stats refresh 30s
  stats uri     /haproxy-status
  stats realm   Haproxy\ Statistics
  stats auth    samuel:samuel
  stats hide-version
  stats admin if TRUE

frontend k8s-https
  bind 0.0.0.0:8443
  mode tcp
  #maxconn 50000
  default_backend k8s-https

backend k8s-https
  mode tcp
  balance roundrobin
  server lab1 10.7.12.201:6443 weight 1 maxconn 1000 check inter 2000 rise 2 fall 3
  server lab2 10.7.12.202:6443 weight 1 maxconn 1000 check inter 2000 rise 2 fall 3
  server lab3 10.7.12.203:6443 weight 1 maxconn 1000 check inter 2000 rise 2 fall 3
EOF
```


### 启动并查看服务状态

```bash
# 启动haproxy
docker run -d --name k8s-haproxy \
-v /etc/haproxy:/usr/local/etc/haproxy:ro \
-p 8443:8443 \
-p 1080:1080 \
--restart always \
haproxy:1.7.8-alpine

# 查看日志
docker logs my-haproxy

# 浏览器查看状态
http://10.7.12.201:1080/haproxy-status
http://10.7.12.202:1080/haproxy-status
```

## 3.2 keepalived 配置
这里选取osixia维护的keepalived镜像

### 拉取并启动服务
```bash
# 拉取keepalived镜像
docker pull osixia/keepalived:1.4.4

# 启动keepalived
# eth0为本次实验网段的所在网卡
docker run --net=host --cap-add=NET_ADMIN \
-e KEEPALIVED_INTERFACE=eth0 \
-e KEEPALIVED_VIRTUAL_IPS="#PYTHON2BASH:['10.7.12.200']" \
-e KEEPALIVED_UNICAST_PEERS="#PYTHON2BASH:['10.7.12.201','10.7.12.202','10.7.12.203']" \
-e KEEPALIVED_PASSWORD=hello \
--name k8s-keepalived \
--restart always \
-d osixia/keepalived:1.4.4
```

### 查看keepalived服务状态

```bash
# 查看日志，会看到两个成为backup 一个成为master
docker logs k8s-keepalived

# 此时会配置 10.7.12.200 到其中一台机器，ping测试
ping -c4 10.7.12.200

# 如果失败后，清理并重新部署
docker rm -f k8s-keepalived
ip a del 10.7.12.200/32 dev eth0
```

# 4 配置启动kubelet

如下操作在所有节点操作
```bash
# 配置kubelet使用国内pause镜像
# 配置kubelet的cgroups
# 获取docker的cgroups
DOCKER_CGROUPS=$(docker info | grep 'Cgroup' | cut -d' ' -f3)
echo $DOCKER_CGROUPS
cat >/etc/sysconfig/kubelet<<EOF
KUBELET_EXTRA_ARGS="--cgroup-driver=$DOCKER_CGROUPS --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.1"
EOF
​
# 启动
systemctl daemon-reload
systemctl enable kubelet && systemctl restart kubelet
```

# 5 部署集群

配置master节点

## 5.1 配置第一个master节点

如下操作在lab1节点操作
### 生成 kubeadm 需要的配置文件

```bash
# 1.11.0 版本 centos 下使用 ipvs 模式会出问题
# 参考 https://github.com/kubernetes/kubernetes/issues/65461
# 1.11.1 之后的版本已经修复了，这里部署使用的是ipvs
# 生成配置文件

CP0_IP="10.7.12.201"
CP0_HOSTNAME="lab1"
cat >kubeadm-master.config<<EOF
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers

apiServerCertSANs:
- "lab1"
- "lab2"
- "lab3"
- "10.7.12.201"
- "10.7.12.202"
- "10.7.12.203"
- "10.7.12.200"
- "127.0.0.1"

api:
  advertiseAddress: $CP0_IP
  controlPlaneEndpoint: 10.7.12.200:8443

etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://$CP0_IP:2379"
      advertise-client-urls: "https://$CP0_IP:2379"
      listen-peer-urls: "https://$CP0_IP:2380"
      initial-advertise-peer-urls: "https://$CP0_IP:2380"
      initial-cluster: "$CP0_HOSTNAME=https://$CP0_IP:2380"
    serverCertSANs:
      - $CP0_HOSTNAME
      - $CP0_IP
    peerCertSANs:
      - $CP0_HOSTNAME
      - $CP0_IP

controllerManagerExtraArgs:
  node-monitor-grace-period: 10s
  pod-eviction-timeout: 10s

networking:
  podSubnet: 10.244.0.0/16

kubeProxy:
  config:
    # mode: ipvs
    mode: iptables
EOF
```
### 初始化

```bash
# 提前拉取镜像
# 如果执行失败 可以多次执行
kubeadm config images pull --config kubeadm-master.config
​
# 初始化
# 注意保存返回的 join 命令
kubeadm init --config kubeadm-master.config
```

初始化结束之后，按照提示，配置kube config

```bash
rm -rf $HOME/.kube
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
同时，这里会提示部署网路插件，这里放在第6步操作


### 打包ca证书到其他master节点
```
# 打包ca相关文件上传至其他master节点
cd /etc/kubernetes && tar cvzf k8s-key.tgz admin.conf pki/ca.* pki/sa.* pki/front-proxy-ca.* pki/etcd/ca.*
scp k8s-key.tgz lab2:~/
scp k8s-key.tgz lab3:~/
ssh lab2 'tar xf k8s-key.tgz -C /etc/kubernetes/'
ssh lab3 'tar xf k8s-key.tgz -C /etc/kubernetes/'
```

## 5.2 配置第二个master节点

如下操作在lab2节点操作

### 生成 kubeadm 需要的配置文件

```bash
# 生成配置文件
CP0_IP="10.7.12.201"
CP0_HOSTNAME="lab1"
CP1_IP="10.7.12.202"
CP1_HOSTNAME="lab2"
cat >kubeadm-master.config<<EOF
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers

apiServerCertSANs:
- "lab1"
- "lab2"
- "lab3"
- "10.7.12.201"
- "10.7.12.202"
- "10.7.12.203"
- "10.7.12.200"
- "127.0.0.1"

api:
  advertiseAddress: $CP1_IP
  controlPlaneEndpoint: 10.7.12.200:8443

etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://$CP1_IP:2379"
      advertise-client-urls: "https://$CP1_IP:2379"
      listen-peer-urls: "https://$CP1_IP:2380"
      initial-advertise-peer-urls: "https://$CP1_IP:2380"
      initial-cluster: "$CP0_HOSTNAME=https://$CP0_IP:2380,$CP1_HOSTNAME=https://$CP1_IP:2380"
      initial-cluster-state: existing
    serverCertSANs:
      - $CP1_HOSTNAME
      - $CP1_IP
    peerCertSANs:
      - $CP1_HOSTNAME
      - $CP1_IP

controllerManagerExtraArgs:
  node-monitor-grace-period: 10s
  pod-eviction-timeout: 10s

networking:
  podSubnet: 10.244.0.0/16

kubeProxy:
  config:
    # mode: ipvs
    mode: iptables
EOF
```


### 配置kubelet
```bash
kubeadm alpha phase certs all --config kubeadm-master.config
kubeadm alpha phase kubelet config write-to-disk --config kubeadm-master.config
kubeadm alpha phase kubelet write-env-file --config kubeadm-master.config
kubeadm alpha phase kubeconfig kubelet --config kubeadm-master.config
systemctl restart kubelet
```

### 添加etcd到集群中
```bash
CP0_IP="10.7.12.201"
CP0_HOSTNAME="lab1"
CP1_IP="10.7.12.202"
CP1_HOSTNAME="lab2"
KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n kube-system etcd-${CP0_HOSTNAME} -- etcdctl --ca-file /etc/kubernetes/pki/etcd/ca.crt --cert-file /etc/kubernetes/pki/etcd/peer.crt --key-file /etc/kubernetes/pki/etcd/peer.key --endpoints=https://${CP0_IP}:2379 member add ${CP1_HOSTNAME} https://${CP1_IP}:2380
kubeadm alpha phase etcd local --config kubeadm-master.config
```

### 配置master加入集群
```bash
# 提前拉取镜像, 可多次执行
kubeadm config images pull --config kubeadm-master.config

# 部署
kubeadm alpha phase kubeconfig all --config kubeadm-master.config
kubeadm alpha phase controlplane all --config kubeadm-master.config
kubeadm alpha phase mark-master --config kubeadm-master.config
```

## 5.3 配置第三个master节点

### 生成 kubeadm 需要的配置文件
```bash
# 生成配置文件
CP0_IP="10.7.12.201"
CP0_HOSTNAME="lab1"
CP1_IP="10.7.12.202"
CP1_HOSTNAME="lab2"
CP2_IP="10.7.12.203"
CP2_HOSTNAME="lab3"
cat >kubeadm-master.config<<EOF
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers

apiServerCertSANs:
- "lab1"
- "lab2"
- "lab3"
- "10.7.12.201"
- "10.7.12.202"
- "10.7.12.203"
- "10.7.12.200"
- "127.0.0.1"

api:
  advertiseAddress: $CP2_IP
  controlPlaneEndpoint: 10.7.12.200:8443

etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://$CP2_IP:2379"
      advertise-client-urls: "https://$CP2_IP:2379"
      listen-peer-urls: "https://$CP2_IP:2380"
      initial-advertise-peer-urls: "https://$CP2_IP:2380"
      initial-cluster: "$CP0_HOSTNAME=https://$CP0_IP:2380,$CP1_HOSTNAME=https://$CP1_IP:2380,$CP2_HOSTNAME=https://$CP2_IP:2380"
      initial-cluster-state: existing
    serverCertSANs:
      - $CP2_HOSTNAME
      - $CP2_IP
    peerCertSANs:
      - $CP2_HOSTNAME
      - $CP2_IP

controllerManagerExtraArgs:
  node-monitor-grace-period: 10s
  pod-eviction-timeout: 10s

networking:
  podSubnet: 10.244.0.0/16

kubeProxy:
  config:
    # mode: ipvs
    mode: iptables
EOF
```

### 配置kubelet
```bash
kubeadm alpha phase certs all --config kubeadm-master.config
kubeadm alpha phase kubelet config write-to-disk --config kubeadm-master.config
kubeadm alpha phase kubelet write-env-file --config kubeadm-master.config
kubeadm alpha phase kubeconfig kubelet --config kubeadm-master.config
systemctl restart kubelet
```

### 添加etcd到集群中
```
CP0_IP="10.7.12.201"
CP0_HOSTNAME="lab1"
CP2_IP="10.7.12.203"
CP2_HOSTNAME="lab3"
KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n kube-system etcd-${CP0_HOSTNAME} -- etcdctl --ca-file /etc/kubernetes/pki/etcd/ca.crt --cert-file /etc/kubernetes/pki/etcd/peer.crt --key-file /etc/kubernetes/pki/etcd/peer.key --endpoints=https://${CP0_IP}:2379 member add ${CP2_HOSTNAME} https://${CP2_IP}:2380
kubeadm alpha phase etcd local --config kubeadm-master.config
```

### 配置master加入集群

```bash
# 提前拉取镜像
kubeadm config images pull --config kubeadm-master.config
​
# 部署
kubeadm alpha phase kubeconfig all --config kubeadm-master.config
kubeadm alpha phase controlplane all --config kubeadm-master.config
kubeadm alpha phase mark-master --config kubeadm-master.config
```



## 5.4 查看node节点
```
kubectl get nodes

```
只有网络插件也安装配置完成之后，才能会显示为ready状态

## 5.5 设置master为可调度状态
​现在可以设置master允许部署应用pod，参与工作负载，现在可以部署其他系统组件。如 dashboard, efk等
```
kubectl taint nodes --all node-role.kubernetes.io/master-
```

# 6 网络插件部署
## 6.1 配置使用网络插件

选择任意master节点操作

## 6.2 下载配置
```bash
mkdir flannel && cd flannel
wget https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
```

## 6.3 修改配置
```bash
# 此处的ip配置要与上面kubeadm的pod-network一致
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
​
# 修改镜像
image: registry.cn-shanghai.aliyuncs.com/gcr-k8s/flannel:v0.10.0-amd64
​
# 如果Node有多个网卡的话，参考flannel issues 39701，
# https://github.com/kubernetes/kubernetes/issues/39701
# 目前需要在kube-flannel.yml中使用--iface参数指定集群主机内网网卡的名称，
# 否则可能会出现dns无法解析。容器无法通信的情况，需要将kube-flannel.yml下载到本地，
# flanneld启动参数加上--iface=<iface-name>
    containers:
      - name: kube-flannel
        image: registry.cn-shanghai.aliyuncs.com/gcr-k8s/flannel:v0.10.0-amd64
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        - --iface=eth0
```
## 6.4 启动并查看
```bash
kubectl apply -f kube-flannel.yml
​
kubectl get pods --namespace kube-system
kubectl get svc --namespace kube-system
```

# 7 添加node节点

我们在初始化第一个master节点的时候，返回了一个加node的命令：
```bash
kubeadm join 10.7.12.200:8443 --token yzb7v7.dy40mhlljt1d48i9 --discovery-token-ca-cert-hash sha256:61ec309e6f942305006e6622dcadedcc64420e361231eff23cb535a183c0e77a
```
如果丢失或已过期可以通过如下获取加入方式
```bash
kubeadm token create --print-join-command
或者
token=$(kubeadm token generate)
kubeadm token create $token --print-join-command --ttl=0
```

# 8 集群基础环境测试

测试容器间的通信和DNS
配置好网络之后，kubeadm会自动部署coredns

如下测试可以在配置kubectl的节点上操作

```bash

启动
kubectl run nginx --replicas=2 --image=nginx:alpine --port=80
kubectl expose deployment nginx --type=NodePort --name=example-service-nodeport
kubectl expose deployment nginx --name=example-service
查看状态
kubectl get deploy
kubectl get pods
kubectl get svc
kubectl describe svc example-service
DNS解析
kubectl run curl --image=radial/busyboxplus:curl -i --tty
nslookup kubernetes
nslookup example-service
curl example-service
访问测试
# 10.96.59.56 为查看svc时获取到的clusterip
curl "10.96.59.56:80"
https://10.7.11.211:8443/api/v1/namespaces/default/services/example-service/proxy/
# 32223 为查看svc时获取到的 nodeport
http://10.7.12.202:32223/
http://10.7.12.203:32223/
清理删除
kubectl delete svc example-service example-service-nodeport
kubectl delete deploy nginx curl
高可用测试
关闭任一master节点测试集群是能否正常执行上一步的基础测试，查看相关信息，不能同时关闭两个节点，因为3个节点组成的etcd集群，最多只能有一个当机。
# 查看组件状态
kubectl get pod --all-namespaces -o wide
kubectl get pod --all-namespaces -o wide | grep lab1
kubectl get pod --all-namespaces -o wide | grep lab2
kubectl get pod --all-namespaces -o wide | grep lab3
kubectl get nodes -o wide
kubectl get deploy
kubectl get pods
kubectl get svc
​
# 访问测试
CURL_POD=$(kubectl get pods | grep curl | grep Running | cut -d ' ' -f1)
kubectl exec -ti $CURL_POD -- sh --tty
nslookup kubernetes
nslookup example-service
curl example-service
```

# 9 负载组件切换
如果kube-proxy用iptables想切换到到ipvs可以直接修改kube-proxy configmap即可
```
kubectl edit configmap kube-proxy -n kube-system
    ipvs:
      minSyncPeriod: 0s
      scheduler: ""
      syncPeriod: 30s
    kind: KubeProxyConfiguration
    metricsBindAddress: 127.0.0.1:10249
    mode: "ipvs" # 加上这个或iptables
    nodePortAddresses: null
```
要重启kube-proxy的容器

# 10 部署Kubernetes Dashboard

## 10.1 获取yaml
下载官方提供的 Dashboard 组件部署的 yaml 文件
wget https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
​
## 10.2 修改 yaml 文件

修改image 为国内地址：
k8s.gcr.io 修改为 registry.cn-hangzhou.aliyuncs.com/google_containers，后续所有 yaml 文件中，只要涉及到 image 的，都需要做同样的修改，因为国内 k8s.gcr.io 这个地址被墙了。

修改 yaml 文件中的 Dashboard Service，暴露服务使外部能够访问
```yaml
kind: Service
apiVersion: v1jiqun
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kube-system
spec:
  ports:
    - port: 443
      targetPort: 8443
  selector:
    k8s-app: kubernetes-dashboard
修改为
kind: Service
apiVersion: v1
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kube-system
spec:
  ports:
    - port: 443
      targetPort: 8443
      nodePort: 31111
  selector:
    k8s-app: kubernetes-dashboard
  type: NodePort
```

## 10.3 启动 Dashboard
```bash
kubectl apply -f kubernetes-dashboard.yaml
```

## 10.4 访问 Dashboard

地址： https://<Your-IP>:31111/

或者访问如下地址：
https://10.7.12.200:8443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy

## 10.5 创建能够访问 Dashboard 的用户

新建文件 account.yaml ，内容如下：
```yaml
# Create Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
# Create ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
```

## 10.6 获取登录 Dashboard 的令牌 （Token）

```bash
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')

```

输出如下
```bash
Name: admin-user-token-f6tct
Namespace: kube-system
Labels: <none>
Annotations: kubernetes.io/service-account.name=admin-user
              kubernetes.io/service-account.uid=81cb9047-7087-11e8-95da-00163e0c5bd1
​
Type: kubernetes.io/service-account-token
​
Data
====
ca.crt: 1025 bytes
namespace: 11 bytes
token: <超长字符串>
```

参考文档:  

https://kubernetes.io/docs/setup/independent/install-kubeadm/

https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/

https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/

https://kubernetes.io/docs/setup/independent/high-availability/

https://sealyun.com/post/k8s-ipvs/

https://www.maogx.win/posts/33/

https://www.jianshu.com/p/31bee0cecaf2

