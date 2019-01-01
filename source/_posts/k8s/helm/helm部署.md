---
title: helm部署
date: 2018-12-29 09:47:19
categories: k8s
tags: [k8s, helm]

---

我们需要在[Helm Realese](https://github.com/helm/helm/releases)页面下载二进制文件，并解压后将可执行文件helm拷贝到/usr/local/bin目录下即可，这样Helm客户端就在这台机器上安装完成了。

现在我们可以查看下版本:
```bash
[root@lab1 ~]# helm version
Client: &version.Version{SemVer:"v2.12.0", GitCommit:"d325d2a9c179b33af1a024cdb5a4472b6288016a", GitTreeState:"clean"}
Error: could not find tiller

```
这里提示无法连接到服务端，接下来我们初始化服务端。

安装 Helm 的服务端程序，我们需要使用到kubectl工具，所以先确保kubectl工具能够正常的访问 kubernetes 集群的apiserver。

然后我们在集群中执行初始化操作：

```bash
$ helm init
或者
$ helm init --upgrade -i registry.cn-hangzhou.aliyuncs.com/google_containers/tiller:$version --stable-repo-url https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
```

由于 Helm 默认会去gcr.io拉取镜像，所以需要用国内的镜像地址替换：
```bash
[root@lab1 helm]# helm init --upgrade --tiller-image liupeng0518/tiller:v2.12.0
```

Helm 服务端正常安装完成后，Tiller默认被部署在kubernetes集群的kube-system命名空间下：
[root@lab1 ~]# kubectl get pod -n kube-system -l app=helm
NAME                           READY     STATUS    RESTARTS   AGE
tiller-deploy-c749b9d9-cdsj5   1/1       Running   0          1m
此时，我们查看 Helm 版本：
```bash
[root@lab1 ~]# helm version
Client: &version.Version{SemVer:"v2.12.0", GitCommit:"d325d2a9c179b33af1a024cdb5a4472b6288016a", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.12.0", GitCommit:"d325d2a9c179b33af1a024cdb5a4472b6288016a", GitTreeState:"clean"}

```
另外一个值得注意的问题是RBAC，我们的 kubernetes 集群是1.11.x版本的，默认开启了RBAC访问控制，所以我们需要为Tiller创建一个ServiceAccount，让他拥有执行的权限，详细内容可以查看 Helm 文档中的Role-based Access Control。 创建rbac.yaml文件：
```bash
[root@lab1 helm]# cat rbac-config.yaml 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system

```
然后使用kubectl创建：
```bash
[root@lab1 helm]# kubectl create -f rbac-config.yaml
serviceaccount "tiller" created
clusterrolebinding "tiller" created
```
创建了tiller的 ServceAccount 后还没完，因为我们的 Tiller 之前已经就部署成功了，而且是没有指定 ServiceAccount 的，所以我们需要给 Tiller 打上一个 ServiceAccount 的补丁：
```bash
[root@lab1 helm]# kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
deployment.extensions/tiller-deploy patched

```
至此, Helm客户端和服务端都配置完成。
可以查看一下仓库：

```bash
[root@lab1 helm]# helm  repo list
NAME         	URL                                                        
stable       	https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts     
local        	http://localhost:8879/charts                               
fabric8      	https://fabric8.io/helm                                    
bitnami      	https://charts.bitnami.com/bitnami                         
aliyun-stable	https://acs-k8s-ingress.oss-cn-hangzhou.aliyuncs.com/charts
```