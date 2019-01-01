---
title: 集群外部访问Kubernetes中的Pods.md
categories: k8s
tags: kubernetes,network
date: 2018-12-29 09:47:19
---


这里有几种方式：

 - hostNetwork
 - hostPort   
 - NodePort   
 - LoadBalancer   
 - Ingress

说是暴露Pod其实跟暴露Service是一回事，因为Pod就是Service的backend。


# hostNetwork: true
这种方式相当于docker中：
docker run -net=host

hostNetwork设置适用于Kubernetes pod（直接定义Pod网络）。当pod配置为 hostNetwork：true 时，在此类pod中运行的应用程序可以直接查看启动pod的主机的网络接口。在主机的所有网络接口上都可以访问到该应用程序。以下是使用主机网络的pod的示例定义：
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: influxdb
spec:
  hostNetwork: true
  containers:
    - name: influxdb
      image: influxdb
```
部署该Pod：
```
$ kubectl create -f influxdb-hostnetwork.yml
```
访问该pod所在主机的8086端口：
```
curl -v http://$POD_IP:8086/ping
```
将看到204 No Content的204返回码，说明可以正常访问。

注意每次启动这个Pod的时候都可能被调度到不同的节点上，所有外部访问Pod的IP也是变化的，而且调度Pod的时候还需要考虑是否与宿主机上的端口冲突，因此一般情况下除非您知道需要某个特定应用占用特定宿主机上的特定端口时才使用hostNetwork: true的方式。

这种Pod的网络模式有一个用处就是可以将网络插件包装在Pod中然后部署在每个宿主机上，这样该Pod就可以控制该宿主机上的所有网络。
# hostPort
这种方式相当于docker中：
docker run -p 8080:8080

hostPort设置适用于 Kubernetes containers（直接定义Pod网络）。容器端口将在 <hostIP>:<hostPort> 中暴露给外部网络，其中hostIP是运行容器的Kubernetes节点的IP地址，hostPort是用户请求的端口。这里有一个示例pod定义：
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: influxdb
spec:
  containers:
    - name: influxdb
      image: influxdb
      ports:
        - containerPort: 8086
          hostPort: 8086
```
hostPort 特性允许在主机IP上公开单个容器端口。使用hostPort将应用程序公开到Kubernetes集群的外部具有与上一节中讨论的hostNetwork方法相同的缺点。当容器重新启动时，主机IP可能更改，同时使用相同hostPort的两个容器无法在同一节点上进行调度，并且hostPort的使用被视为OpenShift上的特权操作。

因为Pod重新调度的时候该Pod被调度到的宿主机可能会变动，这样就变化了，用户必须自己维护一个Pod与所在宿主机的对应关系。

这种网络方式可以用来做 nginx Ingress controller。外部流量都需要通过kubenretes node节点的80和443端口。

# NodePort

# LoadBalancer

# Ingress


参考：
http://alesnosek.com/blog/2017/02/14/accessing-kubernetes-pods-from-outside-of-the-cluster/

https://jimmysong.io/posts/accessing-kubernetes-pods-from-outside-of-the-cluster/