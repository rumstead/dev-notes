# MongoDB Linux Interview Study Guide

## Process Management

### Q: How would you find the process using the most CPU/memory on a Linux system?
**A:** For CPU: `top -o %CPU` or `ps aux --sort=-%cpu | head`
For memory: `top -o %MEM` or `ps aux --sort=-%mem | head`
For more detailed analysis: `htop` provides an interactive view, or use `pidstat -u -p <PID> 1 5` to monitor a specific process over time.

### Q: Explain the difference between SIGTERM, SIGKILL, and SIGHUP signals
**A:**
- `SIGTERM (15)`: Graceful termination request allowing cleanup. Applications can trap and handle this signal.
- `SIGKILL (9)`: Immediate termination that cannot be caught or ignored. May leave resources in inconsistent states.
- `SIGHUP (1)`: Originally meant "hangup", now commonly used to trigger configuration reloads in daemons.

### Q: How would you debug a process that's consuming excessive memory?
**A:**
1. Identify the process: `ps aux --sort=-%mem | head`
2. Check memory maps: `pmap -x <PID>`
3. For Java applications: `jmap -heap <PID>` to analyze heap usage
4. Use `smem -k` to see kernel-adjusted memory usage
5. For detailed analysis: `valgrind --tool=massif` for native applications
6. Check for memory leaks with `/proc/<PID>/status` and monitor `VmRSS` growth over time

## File System Operations

### Q: How do you find files consuming the most disk space?
**A:**
```bash
# Find largest directories
du -h /path | sort -hr | head

# Find largest files
find /path -type f -exec du -h {} \; | sort -hr | head

# More efficient for large filesystems
find /path -type f -size +100M -exec ls -lh {} \; | sort -k5 -hr
```

### Q: What's the difference between soft and hard links?
**A:**
- **Hard links**: Multiple directory entries pointing to the same inode. Cannot span filesystems or link directories. Deletion of one link doesn't affect others.
- **Soft links (symlinks)**: Special files containing a path reference. Can span filesystems and link to directories. Breaks if target is removed.

Check with: `ls -li` (shows inode numbers to identify hard links)

## System Performance

### Q: How would you identify memory leaks in a long-running service?
**A:**
1. Monitor memory usage over time: `ps -o pid,cmd,%mem,rss -p <PID> --sort=-%mem`
2. Use `/proc/<PID>/status` to check `VmRSS` growth pattern
3. For Java applications: `jmap -heap <PID>` for heap dumps
4. Native applications: `valgrind --leak-check=full --show-leak-kinds=all <program>`
5. For production: Use memory profilers like `perf mem record`
6. Check memory allocations: `strace -e trace=memory -p <PID>`

### Q: How would you determine if a system is network-bound or CPU-bound?
**A:**
1. Check CPU utilization: `mpstat 1 5`, look for high %usr or %sys with low %idle
2. Check for network saturation: `sar -n DEV 1 5`, look for throughput approaching interface limits
3. Check disk I/O: `iostat -xz 1 5` for high %util
4. Check load average vs CPU count: `uptime` compared to `nproc`
5. Use `htop` or `top` to correlate CPU and memory usage
6. For comprehensive view: `dstat` shows CPU, disk, net, paging in one view

## Security & Access Control

### Q: How do capabilities work in Linux and containers?
**A:** Linux capabilities divide privileged operations into distinct units:
1. Traditional root privileges are split into ~40 distinct capabilities (CAP_NET_ADMIN, CAP_SYS_ADMIN, etc.)
2. Processes can be granted specific capabilities without full root access
3. In containers, capabilities are restricted by default (drop all, then add specific ones)
4. Docker/containerd use `--cap-add` and `--cap-drop` to manage capabilities
5. In Kubernetes, pod security context allows fine-grained capability control:
   ```yaml
   securityContext:
     capabilities:
       add: ["NET_ADMIN", "SYS_TIME"]
       drop: ["ALL"]
   ```
6. View process capabilities: `getpcaps <PID>` or `cat /proc/<PID>/status | grep Cap`

This granular approach enables principle of least privilege for containerized applications.

### Q: Explain how SELinux/AppArmor affects container security
**A:**
- **SELinux**: Implements Mandatory Access Control (MAC) by labeling processes and resources, then enforcing policy. For containers, it isolates containers from host and each other using unique context labels (e.g., `container_t`).

- **AppArmor**: Profile-based MAC system that restricts program capabilities. Docker generates default profiles to limit container access to host resources.

Both provide additional security beyond UID/GID by preventing privilege escalation and containing compromises. In Kubernetes, annotations or pod security contexts can specify profiles:

```yaml
securityContext:
  seLinuxOptions:
    level: "s0:c123,c456"
```

Check status: `getenforce` (SELinux) or `aa-status` (AppArmor)

---

Remember to relate your answers to experiences with large-scale systems and emphasize automation, observability, and the "allergic to ops work" mindset that MongoDB values in their Platform Engineering team.