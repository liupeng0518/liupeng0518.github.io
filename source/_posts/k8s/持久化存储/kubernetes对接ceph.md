---
title: kubernetes对接ceph
date: 2018-12-29 09:47:19
categories: k8s
tags: [k8s, ceph]

---
# kubernetes持久化存储Ceph RBD
## 静态PV

### 创建ceph secret

在ceph mon节点运行`ceph auth get-key client.admin`命令获取admin的key。定义一个ceph secret文件。

```bash
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret
data:
  key: QVFBOFF2SlZheUJQRVJBQWgvS2cwT1laQUhPQno3akZwekxxdGc9PQ==
```

注意: 文件中的key需要在ceph mon节点使用`ceph auth get-key client.admin | base64`命令对获取的key进行base64。

保存定义的文件，如`ceph-secret.yaml`, 之后创建一个secret:
```bash
# kubectl create -f ceph-secret.yaml 
secret "ceph-secret" created
```

### 创建Persistent Volume

创建一个PV对象，使用下面文件的定义:

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ceph-pv 
spec:
  capacity:
    storage: 2Gi 
  accessModes:
    - ReadWriteOnce 
  rbd: 
    monitors: 
      - mon-hosts:6789
    pool: rbd 
    image: ceph-image
    user: admin
    secretRef:
      name: ceph-secret 
    fsType: ext4 
    readOnly: false
  persistentVolumeReclaimPolicy: Recycle

```

注意： 我们这里直接使用了ceph默认的pool rbd, 由于文件中使用了ceph-image，所以需要在ceph集群中创建该镜像。`rbd create ceph-image -s 128`。

保存定义的PV文件，如ceph-pv.yaml,并创建一个PV:

```
# kubectl create -f ceph-pv.yaml
persistentvolume "ceph-pv" created

```

查看PV的状态是否正常，如果获取的状态是Available则说明该PV处于可用状态，并且没有被PVC绑定。

```
# kubectl get pv
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                     STORAGECLASS   REASON    AGE
ceph-pv     1Gi        RWO            Recycle          Available                                                      56s

```

### 创建Persistent Volume Claim

PVC需要指定访问模式和存储的大小，当前只支持这两个属性，一个PVC绑定到一个PV上。一旦PV被绑定到PVC上就不能被其它的PVC所绑定。它们是一对一的关系。但是多个Pod可以使用同一个PVC进行卷的挂载。

PVC的定义文件如下:

```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ceph-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi

```

保存定义的文件，并基于该文件创建PVC，并检查其状态，如果状态为Bound则说明该PVC已经绑定到PV,如果状态为Pending或Failed则表示PVC绑定PV失败,可用通过查看PVC事件或者kubernetes各个组件日志进行错误排查。

```
#  kubectl create -f task-claim.yaml
persistentvolumeclaim "ceph-claim" created
apiVersion: v1
kind: Secret
metadata:
  name: ceph-kube-secret
  namespace: default
data:
  key: QVFCbEV4OVpmaGJtQ0JBQW55d2Z0NHZtcS96cE42SW1JVUQvekE9PQ== 
type:
  kubernetes.io/rbd
```

```
# kubectl get pvc
NAME              STATUS    VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS   AGE
ceph-claim        Bound     ceph-pv     1Gi        RWO                           6s

```

### 创建Pod

定义一个Pod，在Pod里面启动一个container,并使用PVC去挂载Ceph RBD卷为读写模式。

```
apiVersion: v1
kind: Pod
metadata:
  name: ceph-pod
spec:
  containers:
  - name: ceph-busybox
    image: busybox          
    command: ["sleep", "60000"]
    volumeMounts:
    - name: ceph-vol1       
      mountPath: /usr/share/busybox 
      readOnly: false
  volumes:
  - name: ceph-vol1         
    persistentVolumeClaim:
      claimName: ceph-claim

```

保存Pod的定义文件，如: ceph-pod.yaml。并创建该Pod。之后查看Pod的状态，如果Running则表示卷挂载成功，Pod正常运行。 这样便可以做个简单的操作，进行到该Pod的容器中，向`/usr/share/busybox`目录写入一些数据，之后删除该Pod，在创建一个新的Pod,看之前的数据是否还存在：）

```
#kubectl create -f ceph-pod.yaml 
pod "ceph-pod" created

```

```
kubectl get pods -o wide
NAME                                READY     STATUS    RESTARTS   AGE       IP              NODE
ceph-pod                           1/1       Running   0          20s       10.139.54.211   app31.add.bjdt.qihoo.net

```

## 动态PV

### 创建RBD pool

虽然ceph提供了默认的pool rbd，但是建议创建一个新的pool为kubernetes持久化使用。在ceph的monitors节点创建一个名为`kube`的pool.

```
# ceph osd pool create kube 1024
# ceph auth get-or-create client.kube mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=kube' -o ceph.client.kube.keyring

```

####创建ceph secret

与静态创建的ceph-secret是同一个，这里就不在重复创建。

### 创建kube用户的ceph secret
如果没穿件ceph admin的secret的话 需要同时创建ceph admin secret（步骤相同）

在ceph monitors节点运行命令`ceph auth get-key client.kube`获取kube用户的key。并对该用户key进行base64用于下面的文件。

```
apiVersion: v1
kind: Secret
metadata:
  name: ceph-kube-secret
  namespace: default
data:
  key: QVFCbEV4OVpmaGJtQ0JBQW55d2Z0NHZtcS96cE42SW1JVUQvekE9PQ== 
type:
  kubernetes.io/rbd
```

保存定义的ceph secret文件，如ceph-kube-secret.yaml。执行如下命令创建secret:

```
# kubectl create -f ceph-kube-secret.yaml 
secret "ceph-kube-secret" created

```

查看secret是否创建成功。

```
# kubectl get secret ceph-kube-secret
NAME               TYPE                DATA      AGE
ceph-kube-secret   kubernetes.io/rbd   1         2m

```

### 创建动态RBD StorageClass

在创建StorageClass资源前,先介绍下StorageClass的概念:`StorageClass` 为管理员提供了描述存储`class`的方法。 不同的 `class` 可能会映射到不同的服务质量等级或备份策略，或由群集管理员确定的任意策略。 Kubernetes 本身不清楚各种 `class` 代表的什么。这个概念在其他存储系统中有时被称为“配置文件”。StorageClass不仅仅使用与ceph RBD还可以用于`Cinder`,`NFS`,`Glusterfs`等等。

参考： https://kubernetes.io/docs/concepts/storage/storage-classes/

好了，下面我们来创一个动态的storage class。定义文件如下：

```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: rbd
  annotations:
     storageclass.beta.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/rbd
parameters:
  monitors: 10.7.12.201:6789,10.7.12.202:6789,10.7.12.203:6789
  adminId: admin
  adminSecretName: ceph-secret
  adminSecretNamespace: kube-system
  pool: kube
  userId: kube
  userSecretName: ceph-kube-secret
  userSecretNamespace: default
  fsType: ext4
  imageFormat: "2"
  imageFeatures: "layering"


```

保存文件，并创建storage class。

```
# kubectl create -f rbd-storage-class.yaml 
storageclass "rbd" created

```

检查storage class是否创建成功。

```
# kubectl get storageclass
NAME                PROVISIONER         AGE
rbd (default)   kubernetes.io/rbd   54s

```

### 创建Persistent Volume Claim

具体的描述细节请看创建静态PV时，对PVC的描述。或查看官方文档。下面我们直接定义PVC文件。

```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ceph-claim
spec:
  accessModes:
    rs ReadOnlyMany
  resources:
    requests:
      storage: 1Gi

```

保存定义的文件，并创建该PVC。

```
# kubectl create -f static-ceph-pvc.yaml 
persistentvolumeclaim "ceph-claim" created

```

检查PVC是否创建成功，并查看PVC的状态，如果PVC的状态为Bound则表示已经绑定到PV了。这里详细的说下，在kubernetes中一个指定访问模式和存储大小的PVC只能绑定到指定访问权限和存储大小的PV上，但是这样需要集群管理员手动的创建PV。这样就很麻烦，为了减少管理员的工作。管理员可以创建一个storageclass的资源，当指定规格的PVC请求的时候，StorageClass会动态的给该PVC提供一个PV。 我们查看下该PVC是否被该StorageClass绑定一个符合需求的PV上。我们执行下面的命令:

```
# kubectl get pvc
NAME              STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
ceph-claim        Bound     pvc-c32aca7e-38cd-11e8-af69-f0921c10a7bc   1Gi        ROX            rbd        6s

```

我们看到`ceph-claim`这个PVC已经绑定到了`pvc-c32aca7e-38cd-11e8-af69-f0921c10a7bc`这个PV,而该PV是由名为`rbd`的storageclass动态创建的。

### 创建Pod

我们定义一个Pod来将刚刚创建的PVC挂载到该Pod的容器中去。我们定义的Pod的文件内容如下:

```
apiVersion: v1
kind: Pod
metadata:
  name: static-ceph-pod
spec:
  containers:
  - name: ceph-busybox
    image: busybox
    command: ["sleep", "60000"]
    volumeMounts:
    - name: ceph-vol1
      mountPath: /usr/share/busybox
      readOnly: false
  volumes:
  - name: ceph-vol1
    persistentVolumeClaim:
      claimName: ceph-claim

```

保存定义Pod的文件，我们创建一个Pod:

```
# kubectl get pod static-ceph-pod
NAME               READY     STATUS    RESTARTS   AGE
static-ceph-pod   1/1       Running   0          40s

```

现在，我们已经成功的将该PVC挂载到了Pod中的容器中。
如果集群是二进制部署的话，至此可以完成对接工作，如果你的集群使用kubeadm部署的，那么你需要将ceph-comman的包封装到kube-controller-manager  的images里，因为此image没有包含ceph client。如果不封装，那么需要借助第三方组件，如下。

# kubeadm 对接问题

随着 k8s 1.13 发布， kubeadm 项目逐步进入GA，目前来看 kubeadm 极大简化了k8s部署，趋势已定。  
k8s 可选持久化数据存储的方案比较多，像nfs ceph glusterfs等  
在这里我们通过kubeadm部署完成k8s后，在对接ceph rbd时遇到创建 RBD PersistentVolume 失败:  

```bash  
Failed to provision volume with StorageClass "": failed to create rbd image: executable file not found in $PATH, command output:
```
根据这个 [issue] (https://github.com/kubernetes/kubernetes/issues/38923) 的描述，出错的原因是 kube-controller-manager  的images里，因为此image没有包含ceph client。如果不封装，那么需要借助第三方组件，如下。
容器中不包含 rbd 程序导致 RBD 卷无法正常创建。

目前可以使用kubernetes-incubator/external-storage里的第三方 RBD Provisioner ，[github仓库地址](https://github.com/kubernetes-incubator/external-storage/tree/master/ceph/rbd/deploy)

按照说明：  

### 1. 创建所需资源
```bash
cd ~/kubernetes-incubator/external-storage/ceph/rbd/deploy
NAMESPACE=kube-system # change this if you want to deploy it in another namespace
sed -r -i "s/namespace: [^ ]+/namespace: $NAMESPACE/g" ./rbac/clusterrolebinding.yaml ./rbac/rolebinding.yaml
kubectl -n $NAMESPACE apply -f ./rbac

```
即可成功部署rbd Provisioner。


### 2. 创建sc

```bash
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: dynamic
  annotations:
     storageclass.beta.kubernetes.io/is-default-class: "true"
# provisioner: kubernetes.io/rbd
provisioner: ceph.com/rbd # 这里修改为第三方的provisioner
parameters:
  monitors: x.x.x.x:6789,x.x.x.x:6789,x.x.x.x:6789
  adminId: admin
  adminSecretName: ceph-kube-secret
  adminSecretNamespace: kube-system
  userId: admin
  userSecretName: ceph-kube-secret
  pool: kube
  imageFormat: "2" # 不支持 1 
  imageFeatures: layering

```

### 3. 创建 secret
```bash
apiVersion: v1
kind: Secret
metadata:
  name: ceph-kube-secret
  namespace: kube-system
data:
  # ceph auth get-key client.admin | base64
  key: QVFEZGhLQmJtY2JlTGhBQVE4MThLbEhIck90NjFMU3ZvQWJYZUE9PQ==
type:
  kubernetes.io/rbd

```

### 4. 测试

创建测试pvc
```bash
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ceph-claim
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 1Gi

```
这时会动态创建pvc
```bash
[root@lab1 ceph-sc]# kubectl get pvc
NAME         STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
ceph-claim   Bound     pvc-311c99c2-fc55-11e8-8dca-525400d5b8cc   1Gi        ROX            dynamic        38m

```
### 5. 创建pod
```bash
[root@lab1 ceph-sc]# cat test-pod.yaml 
apiVersion: v1
kind: Pod
metadata:
  name: static-ceph-pod
spec:
  containers:
  - name: ceph-busybox
    image: busybox
    command: ["sleep", "60000"]
    volumeMounts:
    - name: ceph-vol1
      mountPath: /usr/share/busybox
      readOnly: false
  volumes:
  - name: ceph-vol1
    persistentVolumeClaim:
      claimName: ceph-claim


```
这里需要注意：k8s node节点上同样需要安装ceph-common，不然会报错。

# 参考
本文链接：https://www.opsdev.cn/post/Ceph-RBD.html