

nginx dockerfile 可以部署 vue、react 等前端build出来的静态页面服务


问题记录:

1. `”worker_processes auto“ will allc host cpu core number for processes.`


其中nginx的配置为： worker_processes  auto;  
这个配置 worker_processes  auto;  
它会根据服务器的CPU核心数自动设置worker进程的数量, 我们很多节点都是80核的，所以这个worker_processes 就是80 ，这里本身也没什么问题 .  
但是很多微服务资源的分配都只有512M的内存，所以启动的时候会报OOM，接着就是一直输出一堆“2023/11/22 07:45:53 [alert] 1492#1492: epoll_wait() failed (9: Bad file descriptor)”  报错

有两种方式fix：

1. 增加该服务的内存至少位4G
2. 修改worker_processes 为4或8