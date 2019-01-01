---
title: openshift开启监控
date: 2018-12-29 09:47:19
categories: openshift
tags: openshift

---

# OpenShift Metrics部署

OpenShift Metrics 采用Kubernetes原生的kubelet api提供数据，然后使用 heapster进行收集存储到cassandra数据库中，这些监控数据最主要是用来进行 pod autoscalers。

官方部署文档：https://docs.okd.io/3.10/install_config/cluster_metrics.html
## 修改inventory
现有集群中开启，在hosts inventory中添加配置：

```
openshift_metrics_install_metrics=true # 安装metrics
openshift_metrics_hawkular_hostname=hawkular-metrics.oc.com # hawkular域名
openshift_metrics_start_cluster=True # 是否集群启动之后就开始数据收集
openshift_metrics_duration=1 # 数据保留多长时间
openshift_metrics_cassandra_storage_type=dynamic #动态分配pvc

```
## 部署
```
ansible-playbook [-i </path/to/inventory>] <OPENSHIFT_ANSIBLE_DIR>/playbooks/openshift-metrics/config.yml 
```

这里web-console采用pod部署，配置文件在config map里面，所以在部署完监控之后会自动更新web-console的config map添加一条 metricsPublicURL: https://hawkular-metrics.oc.com/hawkular/metrics 信息。   

## 错误处理
我的环境中部署的v3.10.0的openshift，但是openshift的docker hub中并没有tag是v3.10.0 的images，这里是[issus讨论](https://github.com/openshift/origin-metrics/issues/429)  可能是openshift 的ci环境没有构建出v3.10.0的 metrics images。

我们可以使用v3.11.0或v3.9.0的镜像：
```
# https://github.com/openshift/origin-metrics/issues/429
openshift_metrics_cassandra_image: "docker.io/openshift/origin-metrics-cassandra:v3.11.0"
openshift_metrics_hawkular_metrics_image: "docker.io/openshift/origin-metrics-hawkular-metrics:v3.11.0"
openshift_metrics_heapster_image: "docker.io/openshift/origin-metrics-heapster:v3.11.0"
# https://github.com/openshift/origin-metrics/issues/429#issuecomment-417124646
openshift_metrics_schema_installer_image: "docker.io/openshift/origin-metrics-schema-installer:v3.11.0"
```


更多内容可以阅读官方文档。
