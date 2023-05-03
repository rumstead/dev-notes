# Understanding Request and Limits at the cgroup level
## Create a Pod with resource constraints on multiple containers
[busybox.yaml](../manifests/busybox.yaml)

## Find and check out the cgroup subsystems
```shell
kgp cgroup-fun
NAME         READY   STATUS    RESTARTS   AGE
cgroup-fun   2/2     Running   0          49s

# On the node that is running the pod, notice the UUID in the container name
❯ docker ps -a | grep busybox
2403fae93d37   busybox                                                                      "sleep infinity"         About a minute ago   Up About a minute                        k8s_container-two_cgroup-fun_argocd_28c6b84f-4b17-4bac-9ca4-c7c794ebfefc_0
4d798578d792   busybox                                                                      "sleep infinity"         About a minute ago   Up About a minute                        k8s_container-one_cgroup-fun_argocd_28c6b84f-4b17-4bac-9ca4-c7c794ebfefc_0

# navigate to the cgroup filesystem 
lima-rancher-desktop:~$ cd /sys/fs/cgroup

# search for cgroup for the container above
lima-rancher-desktop:/sys/fs/cgroup$ find . -name "*28c6b84f-4b17-4bac-9ca4-c7c794ebfefc*"
./pids/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./hugetlb/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./net_prio/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./perf_event/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./net_cls/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./freezer/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./devices/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./memory/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./blkio/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./cpuacct/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./cpuset/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
./unified/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc
```

## Inspecting the cgroup subsystems
Besides 'unified' each root directory in the above paths are a [cgroup subsystem] (aks resource controllers). If you clicked the link and read the Linux man page, you should have noticed that the subsystems here are V1.

```shell
lima-rancher-desktop:/sys/fs/cgroup$ cd ./cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc

lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ ls -d */
2403fae93d37241926fe9e28e8f188fd2fb33aa41904a2ebbb58bbaf0bfa966e/  3ba285e827a6e0fb3da7be52c6254a5547aa1732a3aa9cc98c20b95e9b8a1875/  4d798578d792d8318c9820f1ecb0c8b34f8c09656cf8c8ee18f16d4e101d5202/
```

We can see three directories under the cgroup-fun pod's cgroup hierarchy. Why three? We have two containers in our pod, "container-one" and "container-two" respectively. 

Let's check the pids and see what they are. 
```shell
lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ cat */tasks
8489
6755
7793

lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ ps -ef | egrep '8489|6755|7793'
6755 65535     0:00 /pause
7793 root      0:00 sleep infinity
8489 root      0:00 sleep infinity

lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ docker ps -a | grep -i 'cgroup-fun'
2403fae93d37   busybox                                                                      "sleep infinity"         4 minutes ago       Up 4 minutes                             k8s_container-two_cgroup-fun_argocd_28c6b84f-4b17-4bac-9ca4-c7c794ebfefc_0
4d798578d792   busybox                                                                      "sleep infinity"         5 minutes ago       Up 5 minutes                             k8s_container-one_cgroup-fun_argocd_28c6b84f-4b17-4bac-9ca4-c7c794ebfefc_0
3ba285e827a6   rancher/mirrored-pause:3.6                                                   "/pause"                 5 minutes ago       Up 5 minutes                             k8s_POD_cgroup-fun_argocd_28c6b84f-4b17-4bac-9ca4-c7c794ebfefc_0
```

Ah, the [pause container]. The pause container "holds" the network namespace configuration of the pod and allows for the workload containers to be able to restart without having to reconstruct the network namespace.

The other two pids, 7793 and 8489, are the containers deployed in our pod. 

## cgroup configuration  
### cpu resources
Circling back to cgroup resource limits... 

Let's check some of the cpu configuration at the pod level.
```shell
lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ cat cpu.shares
15
```
We can see the pod's cpu shares is 15 which matches the total `cpu.requests` from our pod (10m + 5m). Let's check the container's `cpu.shares` and see if they match.

```shell
lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ head -n-0 */cpu.shares
==> 2403fae93d37241926fe9e28e8f188fd2fb33aa41904a2ebbb58bbaf0bfa966e/cpu.shares <==
5

==> 3ba285e827a6e0fb3da7be52c6254a5547aa1732a3aa9cc98c20b95e9b8a1875/cpu.shares <==
2

==> 4d798578d792d8318c9820f1ecb0c8b34f8c09656cf8c8ee18f16d4e101d5202/cpu.shares <==
10
```

Interesting, the 5 and 10 are the two containers we deployed but the 2 is from the pause container. The pause container's overhead is not counted against the pod's cpu requests. Which, makes sense given we would have to account for that in any namespace quotas. 

Poking around some of the other cpu configurations... 

```shell
lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc$ cat cpu.cfs_burst_us cpu.cfs_period_us cpu.cfs_quota_us
0
100000
30000
```

The `cpu.cfs_quota_us` looks like our cpu limits added together * 100. The `us` is for milliseconds. The files translate to allow the CPU to use .03 seconds of the CPU every .1 seconds.

If we check all the cpu configuration for the containers (or directories underneath) we can see their limits as well.

```shell
lima-rancher-desktop:/sys/fs/cgroup/cpu/kubepods/burstable/pod28c6b84f-4b17-4bac-9ca4-c7c794ebfefc# head -n-0 */cpu.cfs*
# container-two
==> 2403fae93d37241926fe9e28e8f188fd2fb33aa41904a2ebbb58bbaf0bfa966e/cpu.cfs_burst_us <==
0

==> 2403fae93d37241926fe9e28e8f188fd2fb33aa41904a2ebbb58bbaf0bfa966e/cpu.cfs_period_us <==
100000

==> 2403fae93d37241926fe9e28e8f188fd2fb33aa41904a2ebbb58bbaf0bfa966e/cpu.cfs_quota_us <==
20000
# pause container
==> 3ba285e827a6e0fb3da7be52c6254a5547aa1732a3aa9cc98c20b95e9b8a1875/cpu.cfs_burst_us <==
0

==> 3ba285e827a6e0fb3da7be52c6254a5547aa1732a3aa9cc98c20b95e9b8a1875/cpu.cfs_period_us <==
100000

==> 3ba285e827a6e0fb3da7be52c6254a5547aa1732a3aa9cc98c20b95e9b8a1875/cpu.cfs_quota_us <==
-1
# container-one
==> 4d798578d792d8318c9820f1ecb0c8b34f8c09656cf8c8ee18f16d4e101d5202/cpu.cfs_burst_us <==
0

==> 4d798578d792d8318c9820f1ecb0c8b34f8c09656cf8c8ee18f16d4e101d5202/cpu.cfs_period_us <==
100000

==> 4d798578d792d8318c9820f1ecb0c8b34f8c09656cf8c8ee18f16d4e101d5202/cpu.cfs_quota_us <==
10000
```

The `cpu.cfs_period_us` is static across all the containers. However, we can see that the `pause` container, which has no cpu limits set, has a -1 `cfs_quota_us` (unlimited). 

More information on [cpu cfs tunables]. 

### enforcement of cpu floors and ceilings

## memory resources


[cgroup subsystem]: https://man7.org/linux/man-pages/man7/cgroups.7.html#CGROUPS_VERSION_1
[pause container]: https://kubernetes.io/docs/concepts/windows/intro/#pause-container
[cpu cfs tunables]: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/resource_management_guide/sec-cpu#sect-cfs