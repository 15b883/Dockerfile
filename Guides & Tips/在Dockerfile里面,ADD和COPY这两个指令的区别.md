### 在Dockerfile里面,ADD和COPY这两个指令的区别主要在于:

1. ADD比COPY更高级,ADD允许<源>是URL,并且可以自动解压缩gzip或tar文件,COPY不可以。

2. COPY只支持简单的文件或目录复制,ADD有自动解压缩和REMOTE URL支持的额外功能。

3. 如果不需要ADD的自动解压缩和REMOTE下载功能,推荐使用COPY,因为它易读、语义更清晰。

4. COPY只接受本地文件或目录作为源,ADD允许来源是URL或者是本地tar文件自动解压。

5. COPY会令镜像层变得没有可缓存,使用ADD可以让镜像层还可以继续被缓存复用。

6. ADD先复制本地文件到容器,如果是可识别的压缩格式会帮助解压,COPY是单纯的复制文件。

总结下来:

- 在多数情况下,推荐使用COPY,因为语意明确,只复制不做额外操作。

- 只有需要自动解压缩或需要复制REMOTE URL文件时,才需要使用ADD。

- 尽量维持镜像的可缓存性,如果源文件没有变化,使用COPY比ADD更好。

### 在Dockerfile中直接执行代码脚本和通过`ENTRYPOINT`或`CMD`指令调用单独的启动脚本，两种方式各有优势和适用场景。

#### 直接在Dockerfile中执行脚本

直接在Dockerfile中使用`RUN`指令执行脚本，通常用于构建镜像时需要的安装步骤，比如安装软件包、配置环境等。这些脚本执行的结果会被打包进镜像中。

**优点**：

1. 简单直接，适合构建阶段需要完成的任务。
2. 执行结果固化到镜像中，不会在容器启动时增加额外的启动时间。

**缺点**：

- 不适合做容器启动时的动态配置和初始化工作。因为这些脚本的执行结果已经在构建镜像时固化。