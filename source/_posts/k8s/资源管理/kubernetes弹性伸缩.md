---
title: kubernetes弹性伸缩
date: 2018-12-24 09:47:19
categories: k8s
tags: [k8s, 弹性伸缩]

---
> 原文：https://rancher.com/blog/2018/2018-08-06-k8s-hpa-resource-custom-metrics/

>Kubernetes的一个很好的功能是能够在运行的服务上自定义autoscale。如果没有autoscaling，则很难适应deployment scaling并满足SLA。本文将向您展示如何使用Horizo​​ntal Pod Autoscale在Kubernetes上自动扩展您的服务。

# Introduction

Kubernetes的一个很好的功能是能够在运行的服务上自定义autoscale。如果没有autoscaling，则很难适应deployment scaling并满足SLA。此功能在Kubernetes集群上称为Horizo​​ntal Pod Autoscaler（HPA）。
# 为什么使用Horizo​​ntal Pod Autoscaling
使用HPA，你可以在deployments里基于资源使用或或自定义指标实现 up/down autoscaling，并根据实时负载状态扩展你的服务。

HPA对您的服务进行了两项直接改进：
 1. 负载高时自动增加计算和内存资源，如果不需要则释放它们。
 2. 根据需要增加/降低性能以实现SLA。

# HPA是如何工作的
HPA会根据获取到的CPU/内存利用率（resource metrics）或基于第三metrics采集工具（Prometheus, Datadog等）提供的自定义指标自动调整replication controller, deployment 或 replica set中的容器数（自定义的最小和最大容量数）普罗米修斯，Datadog等。
HPA实现方式是control loop，其周期由Kubernetes controller manager控制，要使用HPA，那么在启动时需要添加 --horizo​​ntal-pod-autoscaler-sync-period（默认值30s）。

![HPA schema](../.images/horizontal-pod-autoscaler.svg)

# 定义 HPA
HPA是Kubernetes autoscaling API组中的API资源。当前的稳定版本是autoscaling/v1，它仅包括对CPU自动缩放的支持。
要获得对内存和自定义指标扩展的额外支持，它包含在autoscaling/v2beta1和autoscaling/v2beta2中。

[获取更多HPA api object信息](https://git.k8s.io/community/contributors/design-proposals/autoscaling/horizontal-pod-autoscaler.md#horizontalpodautoscaler-object)

HPA可以通过 kubectl 创建，管理和删除它：

- 创建 HPA
  - 通过 manifest: kubectl create -f <HPA_MANIFEST>
  - 通过kubectl(仅支持CPU): kubectl autoscale deployment hello-world --min=2 --max=5 --cpu-percent=50
- 获取 hpa 信息
  - 基本信息: kubectl get hpa hello-world
  - 详细描述: kubectl describe hpa hello-world
- 删除 hpa
  - kubectl delete hpa hello-world

下面是一个简单的 HPA manifest 示例：
```
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: hello-world
spec:
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: hello-world
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 50
  - type: Resource
    resource:
      name: memory
      targetAverageValue: 100Mi
```

  - 使用autoscaling/v2beta1版本的api来定义cpu和内存 metrics
  - 控制hello-world 的deployment自动调度
  - 定义的最小副本数为1
  - 定义的最大副本数为10
  - 扩展触发条件：
    - cpu利用率超过50％
    - 内存使用超过100Mi

# Installation
你需要配置并部署相关资源才能使用HPA的功能。
## Requirements

确认以下信息：
```
- kube-api: requestheader-client-ca-file 
- kubelet: read-only-port at 10255 
- kube-controller: Optional, just needed if distinct values than default are required. 
- horizontal-pod-autoscaler-downscale-delay: "5m0s" 
- horizontal-pod-autoscaler-upscale-delay: "3m0s" 
- horizontal-pod-autoscaler-sync-period: "30s"
```
如果是RKE，那么直接修改配置文件：
```
services:
...
  kube-api: 
    extra_args: 
      requestheader-client-ca-file: "/etc/kubernetes/ssl/kube-ca.pem"
  kube-controller:
    extra_args: 
      horizontal-pod-autoscaler-downscale-delay: "5m0s"
      horizontal-pod-autoscaler-upscale-delay: "1m0s"
      horizontal-pod-autoscaler-sync-period: "30s"
  kubelet:
    extra_args:
      read-only-port: 10255
```
要部署metrics services，必须正确配置和部署Kubernetes集群。

如果是二进制部署 K8S 集群：
```
设置apiserver相关参数
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.pem  \
      --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.pem  \
      --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client-key.pem  \
      --requestheader-allowed-names=aggregator  \
      --requestheader-group-headers=X-Remote-Group  \
      --requestheader-extra-headers-prefix=X-Remote-Extra-  \
      --requestheader-username-headers=X-Remote-User  \
```

这里指定了ca，/etc/kubernetes/pki/front-proxy-ca.pem 文件来自于部署kubernetes集群时，用于Authenticating Proxy功能的API Aggregation的认证 证书。

## Resource metrics
如果HPA想要使用resource metrics，则需要在Kubernetes集群的kube-system命名空间中应用metrics-server。
1. Configure kubectl to connect to the proper Kubernetes cluster.
2. Clone Github metrics-server repo: git clone https://github.com/kubernetes-incubator/metrics-server
3. Install metrics-server package (assuming that Kubernetes is up to version 1.8): kubectl create -f metrics-server/deploy/1.8+/
4. Check that metrics-server is running properly. Check service pod and logs at namespace kube-system
5. Check that the metrics API is accesible from kubectl:
  - If you are accessing directly to the Kubernetes cluster, use the server URL at kubectl config like ‘https://:6443’
```bash
# kubectl get --raw /apis/metrics.k8s.io/v1beta1
{"kind":"APIResourceList","apiVersion":"v1","groupVersion":"metrics.k8s.io/v1beta1","resources":[{"name":"nodes","singularName":"","namespaced":false,"kind":"NodeMetrics","verbs":["get","list"]},{"name":"pods","singularName":"","namespaced":true,"kind":"PodMetrics","verbs":["get","list"]}]}
```
  - If you are accessing the Kubernetes cluster through Rancher, server URL at kubectl config like this: https://<RANCHER_URL>/k8s/clusters/<CLUSTER_ID> You also need to add prefix /k8s/clusters/<CLUSTER_ID> to the API path.
```bash
# kubectl get --raw /k8s/clusters/<CLUSTER_ID>/apis/metrics.k8s.io/v1beta1
{"kind":"APIResourceList","apiVersion":"v1","groupVersion":"metrics.k8s.io/v1beta1","resources":[{"name":"nodes","singularName":"","namespaced":false,"kind":"NodeMetrics","verbs":["get","list"]},{"name":"pods","singularName":"","namespaced":true,"kind":"PodMetrics","verbs":["get","list"]}]}
```

## 自定义 Metrics (Prometheus)


