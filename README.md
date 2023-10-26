## Dockerfile

docker image 存储建议本地搭建一个自己的仓库

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





Build image 

```
# docker build -t python3.10:v1 . 
```

Run docker 

```
# docker run --rm -it python3.10:v1
Hi Python3.10
```







## 支持

- [ ] python3.10
- [ ] python-flask
- [ ] python-fastapi
- [ ] python-django
- [ ] linux-centos
- [ ] linux-ubuntu
- [ ] nginx-js
- [ ] nginx-react
- [ ] nginx-vue
- [ ] go
- [ ] java









## 拓展

### 通过dockerfile 设置build和使用一个单独的机器进行build有什么不通？

使用 Dockerfile 进行构建和在单独的机器上进行构建的主要区别在于可移植性和环境隔离方面。

通过 Dockerfile 进行构建可以确保构建环境的一致性和可移植性，使得构建出来的镜像可以在任何支持 Docker 运行时的机器上进行部署和运行。同时，由于 Docker 使用的是容器虚拟化技术，可以有效地隔离不同的应用和环境，防止构建时的依赖冲突和环境变化等问题。

而在单独的机器上进行构建可能会受到宿主机器上已安装的软件和系统环境的影响，导致构建环境的不一致性和可移植性较差，可能会导致在其他机器上运行出现问题。同时，由于构建机器通常是一台共享的机器，可能会因为其他用户的操作或者系统维护等原因导致构建时间和质量不稳定。

因此，使用 Dockerfile 进行构建是更加推荐的做法，可以确保构建环境的一致性和可移植性，同时保持环境的隔离和稳定性。

使用Dockerfile进行构建的效率通常会更高，因为Dockerfile会将构建过程的各个步骤缓存起来，只需要在某个步骤修改了代码或配置等内容时才需要重新构建。而单独的机器进行构建则需要从头开始构建，无法利用缓存，构建时间通常会更长。此外，使用Dockerfile还能保证构建过程的可重复性，即在任何机器上构建都能得到相同的结果，而单独的机器构建则会受到机器配置和环境等因素的影响，结果可能不一致。



### 在项目的 Dockerfile 中使用两个 FROM 的主要目的是分离构建过程和运行过程,这样可以获得以下几个好处:

1. 更小的运行镜像体积

使用多个 FROM 可以将构建依赖和运行依赖分离到不同的镜像中。构建镜像安装了构建工具链,运行镜像只包含了运行所需的最小环境。这样可以大大缩减运行镜像的体积。

2. 更快的镜像构建速度

构建镜像包含所有构建相关的依赖,而运行镜像只包含应用代码。当应用代码变更时,只需要重新构建运行镜像,可以跳过构建过程带来的时间消耗。

3. 更清晰的镜像职责区分

构建镜像只做构建,运行镜像只做运行。职责清晰,方便维护和扩展。

4. 缓存层级更多

每个 FROM 层级都带有缓存功能,可以充分利用 Docker 的分层缓存机制,加速镜像构建。

常见的方式是第一个 FROM 用来构建,安装所有构建工具。第二个 FROM 专门用于运行,只COPY构建结果的 dist 目录即可。

当然,也要根据实际情况权衡是否需要完全分离构建和运行两个镜像。简单的前端应用可能不需要完全分割。


### 使用两个 FROM 构建的 Docker 镜像不一定会更大,主要取决于如何利用缓存和构建镜像的方式。

对于前端项目来说,一个典型的两个 FROM 的 Dockerfile 流程是:

1. 第一个 FROM node:alpine 作为构建环境,安装所有构建工具链。

2. 在这个FROM中使用 COPY、RUN等命令完成项目的构建,生成最终的 dist 目录。 

3. 第二个 FROM nginx:alpine 作为运行环境,仅 COPY 出的 dist 目录。

这个过程中,第一阶段完成构建后,可以将 node_modules、构建缓存、源代码等都丢弃,不复制到第二个 FROM 中,所以生成的运行镜像体积不会明显增加。

同时,构建镜像有了缓存之后,日常的镜像构建基本上只需要重新构建运行镜像,速度会很快。

正确利用缓存、不复制无用文件,两个 FROM 构建的镜像体积与单个 FROM 相比不会有显著差异,甚至可能会更小。

但也要评估项目实际情况,如果构建过程很简单,也可以直接用一个 FROM 完成构建和运行,无需过度设计。
