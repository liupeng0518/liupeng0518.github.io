---
title: 搭建registry仓库
date: 2018-12-24 09:47:19
categories: k8s
tags: [docker, registry]

---
> 原文: https://github.com/cnadeau/blogs/tree/master/docker-registry

# Private Docker Registry Part 1: basic local example
不使用任何认证信息

这里部署一个无需任何验证的仓库, docker-compose.yml
```yaml
version: '2'
services:
  haproxy:
    image: dockercloud/haproxy:1.6.2
    links:
      - registry
      - registry-ui
    ports:
      - '80:80'
      - '443:443'
      - '5000:5000'
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

  registry:
    build: ./registry
    restart: always
    expose:
      - 5000
    environment:
      TCP_PORTS: '5000'
      VIRTUAL_HOST: '*:5000, https://*:5000'
      FORCE_SSL: 'true'
      REGISTRY_STORAGE_DELETE_ENABLED: 'true'
    volumes:
      - /tmp/local_registry_backup:/var/lib/registry

  registry-ui:
    image: konradkleine/docker-registry-frontend:v2
    restart: always
    environment:
      VIRTUAL_HOST: '*, https://*'
      ENV_DOCKER_REGISTRY_HOST: 'registry'
      ENV_DOCKER_REGISTRY_PORT: 5000
    links:
      - registry
    expose:
      - 80

```
这里使用了自己构建的docker registry image：
```
➜  registry tree
.
├── custom-entrypoint.sh
└── Dockerfile

```

Dockerfile
```yaml
FROM registry:2.5.1

COPY custom-entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

```
`entrypoint.sh`
```bash
#!/bin/sh
set -e

# NOTE: Bring the actual docker-entrypoint.sh code here to make sure the TLS certificate exists before starting the registry
# code from: https://github.com/docker/distribution-library-image/blob/4339e1083299550aeb5915e0d5a5238d159872da/Dockerfile

# Wait for HAproxy to start before updating certificates on startup.
while [ ! -f ${REGISTRY_HTTP_TLS_CERTIFICATE} ];
do
  echo "SSL certificate from letsencrypt not received, waiting 5 second";
  sleep 5;
done

case "$1" in
    *.yaml|*.yml) set -- registry serve "$@" ;;
    serve|garbage-collect|help|-*) set -- registry "$@" ;;
esac

exec "$@"
```



启动：
```
docker-compose up -d
```
仓库地址访问: 127.0.0.1:5000
UI访问：127.0.0.1:80


使用

```
docker tag alpine  127.0.0.1:5000/alpine
docker push 127.0.0.1:5000/alpine

```
这时可以登录UI查看仓库里的镜像信息。


# Private Docker Registry Part 2: let’s add basic authentication
添加基本认证信息 htpasswd方式

docker-compose.auth.yml
```yaml
version: '2'
services:
  registry:
    environment:
      REGISTRY_AUTH: 'htpasswd'
      REGISTRY_AUTH_HTPASSWD_REALM: 'YOUR_DOCKER_REGISTRY_REALM'
      REGISTRY_AUTH_HTPASSWD_PATH: '/httpasswd_storage/htpasswd'
    volumes:
      - ~/htpasswd_backup:/httpasswd_storage
```
这里覆盖了几个变量信息：
REGISTRY_AUTH=htpasswd : sets the authentication method to htpasswd (basic auth)
REGISTRY_AUTH_HTPASSWD_REALM: “YOUR REALM” : the Realm for your docker registry
REGISTRY_AUTH_HTPASSWD_PATH: ‘/httpasswd_storage/htpasswd’ : the full path to the htpasswd files containing your user:pass associations. This file will be shared between the host running your service and the service itself using the volumes definition


生成 htpasswd file

```bash
#Create the htpasswd_backup
mkdir -p ~/htpasswd_backup
docker run --rm --entrypoint htpasswd registry:2 -Bbn <username> "<password>" > ~/htpasswd_backup/htpasswd
```

接下来使用：

```
# login
docker login -u sam localhost:5000

docker pull localhost:5000/alpine
```
当我们登录web UI的时候 也需要 输入用户名密码。


# Private Docker Registry Part 3: let’s use Azure Storage
这一部分主要讲了使用外部存储持久化镜像信息，目前没有Azure，我们可以使用其他存储代替即可。
略

# Private Docker Registry Part 4: let’s secure the registry
启用SSL

docker-compose.ssl.yml
```yaml
version: '2'
services:
  haproxy:
    image: m21lab/haproxy:1.6.2
    links:
      - letsencrypt
    volumes_from:
      - letsencrypt

  letsencrypt:
    image: m21lab/letsencrypt:1.0
    environment:
      DOMAINS: 'YOUR_DOMAIN'
      EMAIL: 'RECOVERYEMAIL@YOUR_DOMAIN'
      OPTIONS: '--staging'

  registry:
    volumes_from:
      - letsencrypt:ro
    environment:
      REGISTRY_HTTP_SECRET: "your-http-secret"
      REGISTRY_HTTP_TLS_CERTIFICATE: /etc/letsencrypt/live/LETSENCRYPT_DOMAIN_ENV_VAR/fullchain.pem
      REGISTRY_HTTP_TLS_KEY: /etc/letsencrypt/live/LETSENCRYPT_DOMAIN_ENV_VAR/privkey.pem

  registry-ui:
    environment:
      FORCE_SSL: 'true'
      ENV_REGISTRY_PROXY_FQDN: 'LETSENCRYPT_DOMAIN_ENV_VAR'
      ENV_DOCKER_REGISTRY_USE_SSL: 1

```

Service Overrides
HAProxy

- 使用不同的image处理SSL流量。

- 链接到新的letsencrypt服务 跳转http请求
- 使用 volumes_from letsenrypt 服务读取收到的SSL证书并动态加载

Let’s Encrypt
此服务用于为托管注册表的域生成有效的CA签名SSL证书。
https://medium.com/@cnadeau_/lets-encrypt-and-haproxy-withdocker-29bdebb6d026

Registry

This service is the docker registry. A lot of configuration was required:

Uses volumes_from letsenrypt service to read the received SSL certificates and dynamically load them
Set registry service specific environment variables:
REGISTRY_HTTP_SECRET=secret: A randomly generated secret used to sign state that may be stored. More information about it here
REGISTRY_HTTP_TLS_CERTIFICATE=public key 
REGISTRY_HTTP_TLS_KEY=private key:
 Those must be mapped to the letsencrypt service volume

启动
```bash
docker-compose -f docker-compose.yml \
               -f docker-compose.auth.yml \
               -f docker-compose.azure.yml \
               -f docker-compose.ssl.yml \
               up -d
```

