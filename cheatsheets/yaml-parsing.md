## Argo CD
### Get active AKS clusters with more than 5 applications
`argocd cluster list -o json | jq -r ' .[] | select(.info.applicationsCount > 5) | [.name, .info.applicationsCount] | @tsv' | grep aks | wc -l`
### Get kustomize output from apps
`argocd apps list -o json | jq -r '.[].spec.source | select(has("helm") | not ) | select(.repoURL != "https://a-url")'`
#### Convert the above to an array of objects
`jq -r '.[].spec.source | select(has("helm") | not ) | select(.repoURL != "https://a-url")' apps.json | jq -s '.' > kust-apps.json`

## Kubernetes
### Get annotations on all ingress resources
`k get ingress -A -o json | jq '.items[] | .metadata.annotations'`
### Get a specific annotation
`kgsec --no-headers -o json | jq '.items[].metadata.annotations["foo/bar.id"]'`
### Get finalizers on Argo CD applications
`k get application --no-headers -o jsonpath='{range .items[*]}{.metadata.finalizers}{"\n"}{end}'`
### Get a specific label with jsonpath
`k get ds -n logging fluent-bit -o jsonpath='{.metadata.labels.kubernetes\.io/cluster-service}'`

## Azure CLI
### Get Azure K8s API Endpoint
`az aks show -g rg -n clustername --subscription sub --query privateFqdn`
### Get AKS version
`az aks show -g rg -n clustername --subscription sub  | grep -E "orchestratorVersion|kubernetesVersion"`
### Get all azure vnets under a resource group
`az network vnet list --subscription ALADDIN-DEV-DEV | jq '.[] | select(.name == "aladdin-dev-dev-muse2-vnet") | .subnets | .[] | .name'`