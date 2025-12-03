# Helpful queries
### Admission webhook failures
```
sum(increase(apiserver_admission_webhook_fail_open_count{}[5m])) by (cluster)
```
### Pods that aren't running and spawned by a Job
```
kube_pod_info{created_by_kind !~ "ReplicaSet|StatefulSet|Pod"}
  * on (pod, namespace)
group_left(label_job, label_controller_uid, phase)
label_replace(
  topk(1, kube_pod_status_phase{phase!="Running"} == 1) by (pod, namespace),
  "phase", "$1", "phase", "(.*)"
)
```
