## Dockerfile

Docker Image 存储建议本地搭建一个自己的仓库

* artifactory（jfrog）
* harbor
* gitHub packages
* aws ecr
* ...


1、先通过docker hub 下载到本地，

2、根据需求修改好dockerfile后 

3、打上tag 

4、上传到自建的仓库

5、内部分享使用（使用内部URL）


| 标签 | 底层/版本 | 体积（相对） | 预装内容（相对） | 兼容性/生态 | 典型适用场景 |
|---|---|---:|---:|---|---|
| `slim` | 通常 Debian 系（未明确代号时随上游） | 小 | 少（删文档/部分工具等） | Debian 生态，兼容性高 | 想比完整版小，但不想换生态 |
| `slim-bookworm` | Debian 12 (bookworm) | 小 | 少 | Debian bookworm 生态，稳定可重复 | 生产常用：小 + 兼容稳 |
| `alpine` | Alpine Linux（musl + apk） | 最小 | 最少 | 与 glibc 相关预编译依赖可能不兼容 | 依赖少、追求极小、确认 musl 兼容 |
| `trixie` | Debian 13 (trixie) | 大 | 多 | Debian trixie 生态 | 需要更多开箱即用工具/更省装包 |
| `slim-trixie` | Debian 13 (trixie) | 小 | 少 | Debian trixie 生态（与 `trixie` 同生态） | 生产镜像想更小、依赖可控 |

Build image 

```
# docker build -t python3.10:v1 . 
```

Run docker 

```
# docker run --rm -it python3.10:v1
Hi Python3.10
```

# docker images save

```shell
docker save -o nginx_image.tar nginx:latest  # Single Image  
docker save -o my_images.tar ubuntu:22.04 redis:alpine # Multiple Images
docker load < filename.tar  # load Images in local docker images
```
