# Understanding shared memory in containers
## Containers
The goal of the exercise is to see how shared memory is handled in containers. When running outside of containers,
a lot of shared libraries and files are shared between processes, saving physical memory. This walkthrough will aim to 
understand how sharing memory is handled in containers.

I will deploy three pods. The first two will
share a layer with a file in it, and the third will have the same file but in a different layer.

### Checking the node
First, let's get the PID of the processes on the node that are running inside a container. 
```bash
❯ kgp -o yaml | yq ' .items[].status.containerStatuses[].containerID'
docker://418bf0a794c558baf253cc9d86035836b477f95b87e036eb08514c9e1a7e4123
docker://0a1849ec113fe424df3ba0c5d6eccbff8843a18bb708d5260a8a46c2be82e0d6
docker://7a863663fd45004395dfc9a9c66ad8ab4b24e5abac59aa756ec39008b9949ed0
```
We can search the cgroup directory structure for the containers. We can do this for each container. 
```bash
lima-rancher-desktop:/sys/fs/cgroup/kubepods/burstable$ find /sys/fs/cgroup/kubepods/ -name *418bf0a794c558baf253cc9d86035836b477f95b87e036eb08514c9e1a7e4123
/sys/fs/cgroup/kubepods/burstable/pod4b7d856a-d973-4e56-9496-698f2cf36521/418bf0a794c558baf253cc9d86035836b477f95b87e036eb08514c9e1a7e4123

lima-rancher-desktop:~$ cat /sys/fs/cgroup/kubepods/burstable/podfa69b419-3aca-47ce-a08a-4e824cede1c4/0a1849ec113fe424df3ba0c5d6eccbff8843a18bb708d5260a8a46c2be82e0d6/cgroup.procs
16145
```
After gathering all the pids, let's see them on the node. 
```bash
lima-rancher-desktop:~$ ps -ef | egrep "16145|17645|14473"
14473 root      0:08 {tail} /usr/bin/coreutils --coreutils-prog-shebang=tail /usr/bin/tail -f /tmp/hello-world.txt
16145 root      0:08 {tail} /usr/bin/coreutils --coreutils-prog-shebang=tail /usr/bin/tail -f /tmp/hello-world.txt
17645 root      0:07 tail -f hello-world.txt
```

Now, let's check the file descriptor of the file that is being shared. 
```bash
lima-rancher-desktop:~$ sudo ls -lsa /proc/17645/fd/3
     0 lr-x------    1 root     root            64 Aug 29 17:36 /proc/17645/fd/3 -> /hello-world.txt
lima-rancher-desktop:~$ sudo ls -lsa /proc/14473/fd/3
     0 lr-x------    1 root     root            64 Aug 29 17:28 /proc/14473/fd/3 -> /tmp/hello-world.txt
lima-rancher-desktop:~$ sudo ls -lsa /proc/16145/fd/3
     0 lr-x------    1 root     root            64 Aug 29 17:33 /proc/16145/fd/3 -> /tmp/hello-world.txt
```
and let's confirm that the inode of the `/tmp/hello-world.txt` are the same. 
```bash
lima-rancher-desktop:~$ sudo stat -Lc %i /proc/16145/fd/3
3183887
lima-rancher-desktop:~$ sudo stat -Lc %i /proc/14473/fd/3
3183887
```
The inode is the same, which means that the file is shared between the two containers.

Finally, let's check the third container. 
```bash
lima-rancher-desktop:~$ sudo stat -Lc %i /proc/17645/fd/3
3052222
```

The inode is different from the other two, which means that the file is not shared between the containers.

## Summary
When containers share layers, the OS is smart enough to share the memory between the processes.
If two processes load a shared library, it gets mapped into both processes VSZ and when the processes use the memory,
they both will have it represented in their RSS. However, the OS is smart enough to only load it into physical memory once. 
Meaning, RSS will overestimate the actual memory used by a process. 