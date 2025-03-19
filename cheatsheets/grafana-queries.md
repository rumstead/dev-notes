# Helpful queries
### Admission webhook failures
```
sum(increase(apiserver_admission_webhook_fail_open_count{}[5m])) by (cluster)
```

