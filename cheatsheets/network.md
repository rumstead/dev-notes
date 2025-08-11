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

## Troubleshooting Interview with Ryan Underwood (August 11th)

### ArgoCD Troubleshooting

#### Common Deployment Issues

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

#### Cross-Environment Deployment Scenarios

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

### Multi-Cloud Kubernetes Management

1. **Cross-Cloud Networking Challenges**
	- VPC peering configurations
	- Service mesh implementation across clouds
	- DNS resolution strategies between cloud providers

2. **Platform Team Leadership**
	- Balancing feature development with operational support
	- Establishing self-service platforms for development teams
	- Creating effective on-call rotations and escalation paths
	- Building automation to eliminate manual operations

### Onboarding Experience Optimization

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