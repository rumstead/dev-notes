# Random Linux / Networking

## HTTPS Connection Establishment

### Complete HTTPS Connection Flow

1. **DNS Resolution**
	- Client resolves domain name to IP address through recursive DNS queries
	- Resolution may involve local DNS cache, ISP DNS servers, and authoritative nameservers

2. **TCP Connection (3-way handshake)**
	- Client sends SYN packet to server port 443
	- Server responds with SYN-ACK packet
	- Client sends ACK packet, completing connection establishment

3. **TLS Handshake**
	- **Client Hello**: Client sends supported TLS versions, cipher suites, and random data
	- **Server Hello**: Server selects TLS version and cipher suite, sends own random data
	- **Certificate Exchange**: Server sends its X.509 certificate containing public key
	- **Certificate Verification**: Client verifies certificate against trusted CA roots
	- **Key Exchange**: Client generates pre-master secret, encrypts it with server's public key
	- **Session Key Derivation**: Both sides derive symmetric session keys from shared secrets
	- **Finished Messages**: Both sides send encrypted "Finished" messages to verify handshake

4. **Encrypted Application Data**
	- HTTP request/response data is encrypted with negotiated symmetric keys
	- Each packet contains MAC (Message Authentication Code) to ensure integrity

## Kubernetes External-to-Internal Request Flow

### External Request to Pod Communication

1. **External Traffic Entry**
	- Request arrives at cloud load balancer (AWS ALB/NLB, GCP LB, etc.)
	- Load balancer forwards to NodePort or directly to ingress controller

2. **Ingress Controller (if present)**
	- Terminates TLS connection
	- Applies routing rules based on hostname/path
	- Forwards request to appropriate Service

3. **Service & kube-proxy**
	- Service provides stable endpoint for pods
	- **kube-proxy modes**:
		- **iptables mode**: Creates NAT rules to redirect traffic to backend pods
		- **IPVS mode**: Uses Linux kernel IPVS for higher-performance load balancing
		- **userspace mode**: Legacy implementation with higher overhead

4. **CNI (Container Network Interface)**
	- **Functions**:
		- Creates pod network interfaces
		- Assigns IP addresses to pods
		- Manages routes between pods across nodes
		- Implements network policies
	- **Common CNI plugins**: Calico, Flannel, Cilium, Weave
	- **Implementation mechanisms**:
		- Overlay networks (VXLAN, GENEVE)
		- Native routing (BGP in Calico)
		- Direct integration with cloud provider networking

5. **Traffic Flow Example**
   ```
   Internet → Load Balancer → Node (NodePort) → kube-proxy (iptables) → 
   CNI overlay network → Pod Network Namespace → Container
   ```

### Q: How would you troubleshoot a service that can't connect to another service?
**A:**
1. Verify basic connectivity: `ping`, `traceroute`
2. Check if service is listening: `ss -tuln | grep <port>` or `netstat -tuln | grep <port>`
3. Test connectivity directly: `telnet <host> <port>` or `nc -zv <host> <port>`
4. Examine firewall rules: `iptables -L -n`
5. Check DNS resolution: `dig <hostname>`, `getent hosts <hostname>`
6. Capture packets: `tcpdump -i <interface> host <target> and port <port> -n`
7. Inspect service logs: `journalctl -u <service>` or application-specific logs

### Q: What command would you use to check which process is listening on port 8080?
**A:**
```bash
# Using ss (preferred)
ss -tulpn | grep :8080

# Using netstat
netstat -tulpn | grep :8080

# Using lsof
lsof -i :8080

# Find process listening on port in specific namespace (for containers)
nsenter -t $(docker inspect -f '{{.State.Pid}}' <container>) -n ss -tulpn | grep :8080
```

### Q: Explain how CNI works in Kubernetes networking
**A:** Container Network Interface (CNI) is a framework that:
1. Dynamically provisions network interfaces to containers
2. Assigns IP addresses and configures routes when pods are created
3. Cleans up resources when pods are deleted
4. Works through plugins (Calico, Flannel, etc.) that implement the CNI spec
5. Handles pod-to-pod connectivity across nodes through overlay networks or native routing
6. Configures network namespaces to isolate pod networking

CNI plugins are invoked by kubelet when pods are scheduled/removed, ensuring consistent networking regardless of underlying infrastructure.

### Q: How does kube-proxy implement service load balancing?
**A:** kube-proxy implements Service abstractions through three modes:
1. **iptables mode** (default): Creates NAT rules in iptables that randomly distribute traffic to backend pods. Rule complexity grows with service count.
2. **IPVS mode**: Uses Linux kernel IPVS for more efficient load balancing with lower latency and better performance at scale. Supports more load balancing algorithms.
3. **userspace mode** (legacy): Listens on ports and proxies connections to backends. Higher overhead.

kube-proxy watches the Kubernetes API server for Service/Endpoint changes and updates rules accordingly.

### ISO stack
Physical Layer: Hardware transmission (cables, radio waves, electrical signals)
Data Link Layer: Frame formatting, MAC addresses, error detection (Ethernet, Wi-Fi)
Network Layer: Routing, IP addressing, packet forwarding (IP, ICMP, OSPF)
Transport Layer: End-to-end communication, reliability (TCP, UDP)
Session Layer: Connection management, session establishment
Presentation Layer: Data formatting, encryption, compression (SSL/TLS, JPEG)
Application Layer: User interfaces, network services (HTTP, FTP, SMTP, DNS)
Memory aid: "Please Do Not Throw Sausage Pizza Away"



## ArgoCD Troubleshooting

### Common Deployment Issues

1. **Sync Failures**
	- **Symptoms**: Application stuck in "OutOfSync" state
	- **Investigation**:
		- Check specific resources with `argocd app get <app-name>`
		- Examine differences with `argocd app diff <app-name>`
		- Verify repository connectivity and webhook configuration
	- **Common causes**:
		- Resource conflicts (manual changes vs GitOps)
		- RBAC permissions insufficient
		- Invalid manifest structure

2. **Health Check Failures**
	- **Investigation**:
		- Review resource-specific health status
		- Check pod logs and events
		- Examine resource dependencies
	- **Common causes**:
		- Readiness/liveness probe failures
		- ConfigMap/Secret missing
		- Resource limits too restrictive

### Cross-Environment Deployment Scenarios

1. **Environment-Specific Failures**
	- **Investigation approach**:
		- Compare configurations between environments
		- Check external dependencies and connectivity
		- Verify resource quotas and limits
		- Examine cluster-specific configurations

2. **Rollback Strategies**
	- Blue/green deployments with ArgoCD
	- History-based rollback approach
	- Data migration considerations during rollbacks

## Multi-Cloud Kubernetes Management

1. **Cross-Cloud Networking Challenges**
	- VPC peering configurations
	- Service mesh implementation across clouds
	- DNS resolution strategies between cloud providers

2. **Platform Team Leadership**
	- Balancing feature development with operational support
	- Establishing self-service platforms for development teams
	- Creating effective on-call rotations and escalation paths
	- Building automation to eliminate manual operations

## Onboarding Experience Optimization

1. **Self-Service Platform Components**
	- Templated service definitions
	- Automated validation and preflight checks
	- Comprehensive documentation with examples
	- Progressive delivery patterns (canary, blue/green)

2. **Team Support Structure**
	- Office hours and support channels
	- Metrics-based improvement of onboarding experience
	- Knowledge sharing and enablement strategies

Remember to emphasize your experience with ArgoCD at scale, multi-cluster deployments, and your leadership approach to building self-service platforms that eliminate manual operations.