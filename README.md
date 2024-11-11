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




Build image 

```
# docker build -t python3.10:v1 . 
```

Run docker 

```
# docker run --rm -it python3.10:v1
Hi Python3.10
```
