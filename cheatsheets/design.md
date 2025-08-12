# System Design Interview Questions and Answers

This document contains common system design interview questions and sample answers tailored for a Lead SRE or Platform Engineering role.

---

## 1. Design a URL Shortener (e.g., bit.ly)

**Key Concepts**: Hashing, database design, read/write optimization, rate limiting, analytics.

**Sample Answer**:
Use base62 encoding of a unique ID or hash of the original URL. Store mappings in a key-value store like Redis for fast access, backed by a persistent DB like PostgreSQL. Use a CDN to cache popular URLs. Add rate limiting and abuse detection. For analytics, stream click data to a system like Kafka and process it asynchronously.

---

## 2. Design a Scalable Notification System

**Key Concepts**: Fan-out architecture, message queues, retries, user preferences.

**Sample Answer**:
Use a pub/sub model with Kafka or RabbitMQ. Notifications are published to a topic and consumed by workers that send emails, push, or SMS. Store user preferences in a DB and filter messages accordingly. Use exponential backoff for retries and dead-letter queues for failures. Scale horizontally by adding more consumers.

---

## 3. Design a Global Load Balancer

**Key Concepts**: DNS-based routing, health checks, failover, geo-distribution.

**Sample Answer**:
Use DNS-based load balancing with latency-based routing. Each region has its own load balancer (e.g., AWS ALB), and a global traffic manager (like Route 53 or Cloudflare) routes requests. Health checks ensure only healthy regions receive traffic. For failover, use active-passive or active-active setups with replication.

---

## 4. Design a CI/CD System

**Key Concepts**: GitOps, pipelines, rollback, artifact storage, security.

**Sample Answer**:
Use Git as the source of truth. ArgoCD syncs changes to Kubernetes. Argo Workflows handle testing and build stages. Artifacts are stored in S3 or Artifactory. Use RBAC for access control and Vault for secrets. Canary deployments are gated by metrics and automated rollback is triggered on failure.

---

## 5. Design a Metrics Collection System

**Key Concepts**: Time-series databases, scraping, aggregation, alerting.

**Sample Answer**:
Use Prometheus to scrape metrics from services. Store data in a time-series DB like Thanos or Cortex for long-term retention. Grafana visualizes metrics. Alerts are configured via Alertmanager and tied to SLOs. Use exporters for system-level metrics and custom instrumentation for business metrics.

---

## 6. Design a Secure Secrets Management System

**Key Concepts**: Encryption, access control, audit logging, rotation.

**Sample Answer**:
Use HashiCorp Vault to store secrets. Access is controlled via policies and integrated with Kubernetes via sidecar injection or CSI drivers. Secrets are encrypted at rest and in transit. Audit logs track access. Rotation is automated via Vault’s dynamic secrets feature or external scripts.

---

## 7. Design a Service Discovery System

**Key Concepts**: DNS, service registry, health checks, dynamic updates.

**Sample Answer**:
Use a service registry like Consul or etcd. Services register themselves and update health status. Clients query the registry or use DNS-based discovery. For Kubernetes, use built-in service discovery via DNS and labels. Add caching and retries for resilience.

---

## 8. Design a Multi-Tenant SaaS Platform

**Key Concepts**: Isolation, scalability, billing, RBAC.

**Sample Answer**:
Use namespaces or separate clusters for tenant isolation. Shared services like auth and billing are multi-tenant aware. Data is partitioned per tenant using tenant IDs. RBAC ensures access control. Use feature flags and config management for customization.

---
