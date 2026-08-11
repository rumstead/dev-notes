# Kubernetes API Server

## Responses 
### 410 Gone

Returned when a LIST or WATCH request uses a stale resourceVersion that has been compacted by etcd.
Most commonly triggered during paginated LISTs using limit= and follow‑up continue tokens.

Example scenario:

pods?limit=500&resourceVersion=0 → first page succeeds → second page uses a continue token → etcd has compacted that revision → 410.
Does not mean the object was deleted; it means “your cursor is invalid; start over.”


### 429 Too Many Requests

Caused by API Priority & Fairness (APF) or global inflight request limits.
Happens when:

- **A client exceeds its APF concurrency share**
- **The API server is saturated**
- **Many controllers or agents restart and create LIST/WATCH storms**


Can affect all clients, even with different service accounts or user agents, if:

- **They fall into the same APF priority level**
- **Global inflight limits are full**

## Argo CD Issues

### Core Problem Pattern

Frequent intermittent `LIST` failures from Argo CD to AKS API servers, returning `4xx`/`5xx` and correlating directly with cluster disconnects.

`WATCH` operations often stall or end with `http2: stream closed` / `connection reset by peer`, suggesting network instability rather than pure API‑server load.

Clear indicators this is not etcd, and not an Argo CD bug, but likely latency or intermittent packet loss between Argo CD and the AKS control plane.

`LIST` is the real bottleneck, not `WATCH`. `LIST` failures force a full cluster cache rebuild -> more load -> more `LIST`s -> more failures.

When `LIST` fails with `410 Gone`, it's due to expired or invalid historical versions / continue tokens, which happens more often under frequent disconnects.

Argo CD logs, Grafana metrics, and ADX logs show timeouts around `~60s`, matching the default Argo CD client timeout, reinforcing the latency theory.

Connection resets have no `userAgent` in `kube-apiserver` logs, further suggesting network‑level resets rather than Argo-specific failures.
Research clusters show the highest error volume.

