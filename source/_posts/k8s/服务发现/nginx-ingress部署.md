---
title: nginx-ingress部署
date: 2018-12-29 09:47:19
categories: k8s
tags: [k8s, ingress]

---

# nginx-ingress 介绍
Ingress 是一种 Kubernetes 资源，也是将 Kubernetes 集群内服务暴露到外部的一种方式。   
Nginx Ingress Controller 是 Kubernetes Ingress Controller 的一种实现，作为反向代理将外部流量导入集群内部，实现将 Kubernetes 内部的 Service 暴露给外部，这样我们就能通过公网或内网直接访问集群内部的服务。

目前helm仓库中已经有了nginx-ingress的资源。  

项目地址: https://kubernetes.github.io/ingress-nginx  

github地址: https://github.com/kubernetes/ingress-nginx/  

# 流量导入方式
要想暴露内部流量，就需要让 Ingress Controller 自身能够对外提供服务，我们可以选择一下方式：

Ingress Controller 使用 Deployment 部署，Service 类型指定为 LoadBalancer

	- 可以通过 Cloud Provider 提供loadbalancer
	- 可以通过指定external ip 设置vip方式

Ingress Controller 使用 DeamonSet 部署，Pod 指定 hostnetwork或hostPort 来暴露端口

	- 没有高可用保证，需要自己实现
	- 需要占用宿主机端口

Ingress Controller 使用 NodePort方式

	- 没有高可用保证，需要自己实现
	- 需要占用宿主机端口

# LoadBalancer 方式导入流量
## 云厂商 Cloud Provider 
这种方式部署 Nginx Ingress Controller 最简单，只要保证上面说的前提：集群有 Cloud Provider 并且支持 LoadBalancer，如果你是使用云厂商的 Kubernetes 集群，保证你集群所使用的云厂商的账号有足够的余额，执行下面的命令一键安装：
```bash
helm install --name nginx-ingress --namespace kube-system stable/nginx-ingress
```

因为 stable/nginx-ingress 这个 helm 的 chart 包默认就是使用的这种方式部署。

部署完了我们可以查看 LoadBalancer 给我们分配的 IP 地址：
```bash
$ kubectl get svc -n kube-system
NAME                            TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
nginx-ingress-controller        LoadBalancer   10.3.255.123   120.27.122.135   80:30113/TCP,443:32564/TCP   1h
```

EXTERNAL-IP 就是我们需要的外部 IP 地址，通过访问它就可以访问到集群内部的服务了，我们可以将想要的域名配置这个IP的DNS记录，这样就可以直接通过域名来访问了。具体访问哪个 Service, 这个就是我们创建的 Ingress 里面所配置规则的了，可以通过匹配请求的 Host 和 路径这些来转发到不同的后端 Service.





# Bare Metal 环境下流量导入
在使用 Bare Metal 的时候可以有几种方式：

	 - hostNetwork 
	 - hostPort
	 - nodePort
	 - externalIP

## EXTERNAL-IP

### kube-proxy ipvs
在我们的环境中，kube-proxy开启了ipvs模式，ingress controller采用externalIp的Service，externalIp指定的就是VIP，vip会由kube-proxy ipvs接管。
实验环境：
```bash
[root@lab1 ingeress]# kubectl get node -owide 
NAME      STATUS    ROLES     AGE       VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION               CONTAINER-RUNTIME
lab1      Ready     master    1d        v1.11.5   10.7.12.201   <none>        CentOS Linux 7 (Core)   3.10.0-862.11.6.el7.x86_64   docker://17.3.2
lab2      Ready     master    1d        v1.11.5   10.7.12.202   <none>        CentOS Linux 7 (Core)   3.10.0-862.11.6.el7.x86_64   docker://17.3.2
lab3      Ready     master    1d        v1.11.5   10.7.12.203   <none>        CentOS Linux 7 (Core)   3.10.0-862.11.6.el7.x86_64   docker://17.3.2
lab4      Ready     <none>    1d        v1.11.5   10.7.12.204   <none>        CentOS Linux 7 (Core)   3.10.0-862.11.6.el7.x86_64   docker://17.3.2
[root@lab1 ingeress]# 
```
此时我们部署:
```bash
helm install --name nginx-ingress --set "rbac.create=true,controller.service.externalIPs[0]=10.7.12.210" stable/nginx-ingress

```
这种方式提供了一种，基于 IPVS 的 Bare metal环境下Kubernetes Ingress边缘节点的高可用。
如果这里不适用的ipvs，那么需要使用keepalived代替 提供vip支持。

这时我们去任意节点查看：
```bash
[root@lab1 ingeress]# ip a sh kube-ipvs0
7: kube-ipvs0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN group default 
    link/ether 9a:e7:21:a4:e5:ab brd ff:ff:ff:ff:ff:ff
    inet 10.96.0.1/32 brd 10.96.0.1 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.96.0.10/32 brd 10.96.0.10 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.98.162.41/32 brd 10.98.162.41 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.104.239.107/32 brd 10.104.239.107 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.103.35.242/32 brd 10.103.35.242 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.104.65.25/32 brd 10.104.65.25 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.99.227.84/32 brd 10.99.227.84 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.7.12.210/32 brd 10.7.12.210 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
    inet 10.104.157.87/32 brd 10.104.157.87 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
```
可以看到 10,7.12.210这个ip绑定到了 kube-ipvs0 上了

在几台节点宿主机上查看，我们可以看到 ExternalIP 的 Service 是通过 Kube-Proxy对外暴露的，这里的 10.7.12.210是内网 IP。 实际生产应用中是需要通过边缘路由器或全局统一接入层的负载均衡器将到达公网 IP 的外网流量转发到这个内网 IP 上，外部用户再通过域名访问集群中以 Ingress 暴露的所有服务。

```
[root@lab1 ingeress]# sudo netstat -tlunp|grep kube-proxy|grep -E '80|443'
tcp        0      0 10.7.12.210:443         0.0.0.0:*               LISTEN      3127/kube-proxy     
tcp        0      0 10.7.12.210:80          0.0.0.0:*               LISTEN      3127/kube-proxy 
```

这时我们访问：

```
[root@lab1 deploy]# curl http://10.7.12.210
default backend - 404

[root@lab1 deploy]# curl -k  https://10.7.12.210
default backend - 404

[root@lab1 ingeress]# curl -I http://10.7.12.210/healthz/
HTTP/1.1 200 OK
Server: nginx/1.13.8
Date: Thu, 13 Dec 2018 04:44:47 GMT
Content-Type: text/html
Content-Length: 0
Connection: keep-alive
Strict-Transport-Security: max-age=15724800; includeSubDomains;

[root@lab1 ingeress]# curl -I --insecure http://10.7.12.210/healthz/
HTTP/1.1 200 OK
Server: nginx/1.13.8
Date: Thu, 13 Dec 2018 04:45:00 GMT
Content-Type: text/html
Content-Length: 0
Connection: keep-alive
Strict-Transport-Security: max-age=15724800; includeSubDomains;


```

创建测试
```bash
[root@lab1 ingeress]# cat my-nginx.yaml 
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: my-nginx
spec:
  replicas: 1
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    app: my-nginx
spec:
  ports:
  - port: 80
    protocol: TCP
    name: http
  selector:
    run: my-nginx
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: my-nginx
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: my-nginx
    http:
      paths:
      - path: /
        backend:
          serviceName: my-nginx
          servicePort: 80


```
访问：
```bash
[root@lab1 ingeress]# curl my-nginx
...
<title>Welcome to nginx!</title>
...

```


查看相关信息
```bash
[root@lab1 ingeress]# kubectl get svc
kub	NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
kubernetes                      ClusterIP      10.96.0.1       <none>        443/TCP                      1d
my-nginx                        ClusterIP      10.104.65.25    <none>        80/TCP                       31m
nginx-ingress-controller        LoadBalancer   10.99.227.84    10.7.12.210   80:31970/TCP,443:30512/TCP   1m
nginx-ingress-default-backend   ClusterIP      10.104.157.87   <none>        80/TCP                       1m
nobby-scorpion-mariadb          ClusterIP      10.103.35.242   <none>        3306/TCP                     18h
[root@lab1 ingeress]# kubectl get pod
NAME                                             READY     STATUS    RESTARTS   AGE
my-nginx-59497d7745-f785f                        1/1       Running   0          32m
nginx-ingress-controller-58bff448cb-6hf9s        1/1       Running   1          1m
nginx-ingress-default-backend-7744786499-wnhsh   1/1       Running   0          1m
nobby-scorpion-mariadb-756d49cfb8-z7jtb          1/1       Running   0          18h
static-ceph-pod                                  1/1       Running   1          19h
[root@lab1 ingeress]# kubectl get ing
NAME       HOSTS      ADDRESS   PORTS     AGE
my-nginx   my-nginx             80        32m

```

### kube-proxy iptables
这种方式需要外部提供vip高可用

这里我们指定controller.service.externalIPs[0]为vip地址，如下方式部署：
```bash
helm install --name nginx-ingress --set "rbac.create=true,controller.service.externalIPs[0]=10.7.12.210,controller.service.externalIPs[1]=10.7.12.201,controller.service.externalIPs[2]=10.7.12.202" stable/nginx-ingress

```
部署之后，我们这里只是指定了vip地址，但是环境中并未真实提供vip地址，
那么之后可以通过keepalived方式提供vip。


## hostnetwork/hostport
这种方式实际是使用集群内的某些节点来暴露流量，使用 DeamonSet 部署，保证让符合我们要求的节点都会启动一个 Nginx 的 Ingress Controller 来监听端口，这些节点我们叫它 边缘节点，因为它们才是真正监听端口，让外界流量进入集群内部的节点，这里我使用集群内部的一个节点来暴露流量，并且 80 和 443 端口没有被其它占用。

nodeport 则是在所有集群节点启动监听端口。

接下来的实现方式是 hostNetwork：
### 挑选边缘节点
首先，查看集群节点：
```bash
➜  ~ kubectl get node
NAME   STATUS   ROLES    AGE   VERSION
lab1   Ready    master   17h   v1.11.5
lab2   Ready    master   17h   v1.11.5
lab3   Ready    master   17h   v1.11.5
lab4   Ready    <none>   17h   v1.11.5

```

我想要 lab4 这个节点作为 边缘节点 来暴露流量，我来给它加个 label，以便后面我们用 DeamonSet 部署 Nginx Ingress Controller 时能绑到这个节点上，我这里就加个名为 node:edge 的 label :
```bash
$ kubectl label node lab4 node=edge
node "lab4" labeled
```

如果 label 加错了可以这样删掉:
```bash
$ kubectl label node lab4 node-
node "lab4" labeled
```
### 部署ingress
我们可以这样查看版本：
```bash
[root@lab1 ~]# helm search nginx-ingress
NAME                            	CHART VERSION	APP VERSION	DESCRIPTION                                                 
aliyun-stable/nginx-ingress     	0.16.1       	0.12.0-2   	An nginx Ingress controller that uses ConfigMap to store ...
bitnami/nginx-ingress-controller	3.1.1        	0.21.0     	Chart for the nginx Ingress controller                      
local/nginx-ingress             	0.9.5        	0.10.2     	An nginx Ingress controller that uses ConfigMap to store ...
stable/nginx-ingress            	0.9.5        	0.10.2     	An nginx Ingress controller that uses ConfigMap to store ...
stable/nginx-lego               	0.3.1        	           	Chart for nginx-ingress-controller and kube-lego            

```

注意： 目前有的k8s版本使用hostport不生效，这里我是使用的hostnetwork方式。

接下来我们覆盖一些默认配置来安装，我们选择stable的0.9.5，注意这里集群开启了rbac，所以这里也要开启rbac支持，否则会导致controller无法启动。
同时我们这里选择了hostNetwork的方式：
```bash
helm install stable/nginx-ingress \
  --namespace kube-system \
  --name nginx-ingress \
  --version=0.9.5 \
  --set rbac.create=true \
  --set controller.kind=DaemonSet \
#  --set controller.daemonset.useHostPort=true \
  --set controller.hostNetwork=true \
  --set controller.nodeSelector.node=edge \
  --set controller.service.type=ClusterIP
```
这里指定的参数具体可以在[github](https://github.com/helm/charts/tree/master/stable/nginx-ingress)主页查看：


可以看下是否成功启动:

```bash
[root@lab1 ~]# kubectl get pods -owide -n kube-system | grep nginx-ingress
nginx-ingress-controller-9nxsw                   1/1       Running   0          1m        10.244.3.198   lab4      <none>
nginx-ingress-default-backend-7744786499-kmfrx   1/1       Running   0          1m        10.244.3.199   lab4      <none>

```
如果状态不是 Running 可以查看下详情:
```bash
$ kubectl describe -n kube-system po/nginx-ingress-controller-9nxsw
```
这里我们可以在lab4节点上查看：
```bash

# 查看宿主机端口监听
[root@lab4 ~]# ss -antlp|grep '80\|443'
LISTEN     0      128          *:443                      *:*                   users:(("nginx",pid=28179,fd=15),("nginx",pid=28175,fd=15),("nginx",pid=27967,fd=15))
LISTEN     0      128          *:18080                    *:*                   users:(("nginx",pid=28179,fd=17),("nginx",pid=28175,fd=17),("nginx",pid=27967,fd=17))
LISTEN     0      128          *:80                       *:*                ```
[root@lab1 deploy]# curl http://10.7.12.204
default backend - 404

[root@lab1 deploy]# curl -k  https://10.7.12.204
default backend - 404

```   users:(("nginx",pid=28179,fd=13),("nginx",pid=28175,fd=13),("nginx",pid=27967,fd=13))
LISTEN     0      128         :::443                     :::*                   users:(("nginx",pid=28179,fd=16),("nginx",pid=28175,fd=16),("nginx",pid=27967,fd=16))
LISTEN     0      128         :::18080                   :::*                   users:(("nginx",pid=28179,fd=18),("nginx",pid=28175,fd=18),("nginx",pid=27967,fd=18))
LISTEN     0      128         :::80                      :::*                   users:(("nginx",pid=28179,fd=14),("nginx",pid=28175,fd=14),("nginx",pid=27967,fd=14))

# 查看宿主机所启动的进程
[root@lab4 ~]# ps aux|grep nginx|grep -v grep
root     27862  0.0  0.0   4040   356 ?        Ss   18:31   0:00 /usr/bin/dumb-init /nginx-ingress-controller --default-backend-service=kube-system/nginx-ingress-default-backend --election-id=ingress-controller-leader --ingress-class=nginx --configmap=kube-system/nginx-ingress-controller
root     27872  0.6  0.2  39700 19892 ?        Ssl  18:31   0:02 /nginx-ingress-controller --default-backend-service=kube-system/nginx-ingress-default-backend --election-id=ingress-controller-leader --ingress-class=nginx --configmap=kube-system/nginx-ingress-controller

```
这时会在lab4上启动进程监听80和443：
可以通过浏览器访问 lab4或ip：

```
[root@lab1 deploy]# curl http://10.7.12.204
default backend - 404

[root@lab1 deploy]# curl -k  https://10.7.12.204
default backend - 404

```

运行成功我们就可以创建 Ingress 来将外部流量导入集群内部啦，外部 IP 是我们的 边缘节点 的 IP，公网和内网 IP 都算，我用的 lab4 这个节点，并且它有公网 IP，我就可以通过公网 IP 来访问了，如果再给这个公网 IP 添加 DNS 记录，我就可以用域名访问了。
### 高可用
此时部署成功之后，这里同样需要通过keepalived或外部LB提供高可用

### 测试
我们来创建一个服务测试一下，先创建一个 my-nginx.yaml
```bash
vi my-nginx.yaml
粘贴以下内容：

apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: my-nginx
spec:
  replicas: 1
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    app: my-nginx
spec:
  ports:
  - port: 80
    protocol: TCP
    name: http
  selector:
    run: my-nginx
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: my-nginx
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - http:
      paths:
      - path: /
        backend:
          serviceName: my-nginx
          servicePort: 80
```
创建：
```
kubectl apply -f my-nginx.yaml
```

查看状态：
```bash
[root@lab1 ingeress]# kubectl get pod
NAME                                      READY     STATUS    RESTARTS   AGE
my-nginx-59497d7745-h6h4r                 1/1       Running   0          30s
nobby-scorpion-mariadb-756d49cfb8-z7jtb   1/1       Running   0          2h
static-ceph-pod                           1/1       Running   0          2h
[root@lab1 ingeress]# kubectl get svc
NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes               ClusterIP   10.96.0.1       <none>        443/TCP    1d
my-nginx                 ClusterIP   10.99.42.39     <none>        80/TCP     34s
nobby-scorpion-mariadb   ClusterIP   10.103.35.242   <none>        3306/TCP   2h
[root@lab1 ingeress]# kubectl get ing
NAME       HOSTS      ADDRESS   PORTS     AGE
my-nginx   my-nginx             80        36s

```
没有dns，那么可以通过配置/etc/hsots 方式解析。

然后浏览器通过域名访问，可以看到 Welcome to nginx! 这个 nginx 默认的主页。

注意：定义 Ingress 的时候最好加上 kubernetes.io/ingress.class 这个 annotation，在有多个 Ingress Controller 的情况下让请求能够被我们安装的这个处理（云厂商托管的 Kubernetes 集群一般会有默认的 Ingress Controller)


## nodeport
这里我们使用官方yaml文件方式部署

github地址: https://github.com/kubernetes/ingress-nginx/  


官方部署文档：
https://github.com/kubernetes/ingress-nginx/blob/nginx-0.20.0/docs/deploy/index.md

我们可以如下方式直接部署：

```bash
git clone https://github.com/kubernetes/ingress-nginx.git
git checkout nginx-0.20.0
cd ~/ingress-nginx/deploy
kubectl apply -f mandatory.yaml

# baremetal方式部署
# 这里可以修改yaml，指定nodePort，默认是动态生成
kubectl apply -f provider/baremetal/service-nodeport.yaml 
```

部署完成之后，可以访问nodePort，同样会返回;

default backend - 404

# 参考

https://imroc.io/posts/kubernetes/use-nginx-ingress-controller-to-expose-service/

https://blog.frognew.com/2018/06/kubernetes-ingress-1.html