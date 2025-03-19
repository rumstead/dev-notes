## Argo CD
### Get active AKS clusters with more than five applications
`argocd cluster list -o json | jq -r ' .[] | select(.info.applicationsCount > 5) | [.name, .info.applicationsCount] | @tsv' | grep aks | wc -l`
### Get kustomize output from apps
`argocd apps list -o json | jq -r '.[].spec.source | select(has("helm") | not ) | select(.repoURL != "https://a-url")' | jq -s`
Use the above URL to filter out repos you don't want to lint, like cluster config based ones :)
#### Convert the above to an array of objects
`jq -r '.[].spec.source | select(has("helm") | not ) | select(.repoURL != "https://a-url")' apps.json | jq -s '.' > kust-apps.json`
#### Get all "application like" resources under an argo cd application
`argocd app list -o json | jq '[.[] | select(.status.resources != null)  | .status?.resources?[] | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet")] | length'`
#### Get all non-prod clusters
```
argocd cluster list -o json > clusters.json
cat clusters.json | jq '.[] | select(.labels."kubernetes.cnp.io\/cluster.prod" == "false") | .labels."kubernetes.cnp.io\/environment"' | sort | uniq | sed -e 's/"//g'
```
#### Get all applicationsets with a cluster generator
```
k get applicationset --no-headers -o json | jq '[.items[] | select(.spec.generators[]? | .. | select(type == "object" and has("clusters"))) | .metadata.name] | length
```

## Kubernetes
### Get annotations on all ingress resources
`k get ingress -A -o json | jq '.items[] | .metadata.annotations'`
### Get a specific annotation
`kgsec --no-headers -o json | jq '.items[].metadata.annotations["foo/bar.id"]'`
### Get finalizers on Argo CD applications
`k get application --no-headers -o jsonpath='{range .items[*]}{.metadata.finalizers}{"\n"}{end}'`
### Get a specific label with jsonpath
`k get ds -n logging fluent-bit -o jsonpath='{.metadata.labels.kubernetes\.io/cluster-service}'`
### Get all pod images
`kgp -A -o yaml | yq '.items[] | .spec.containers[].image'`

## Azure CLI
### Get Azure K8s API Endpoint
`az aks show -g rg -n clustername --subscription sub --query privateFqdn`
### Get AKS version
`az aks show -g rg -n clustername --subscription sub  | grep -E "orchestratorVersion|kubernetesVersion"`
### Get all azure vnets under a resource group
`az network vnet list --subscription sub | jq '.[] | select(.name == vnet-name") | .subnets | .[] | .name'`