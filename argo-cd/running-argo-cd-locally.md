# Running Argo CD locally
## Turning off TLS between the pods
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  controller.repo.server.plaintext: "true"
  reposerver.disable.tls: "true"
  server.repo.server.plaintext: "true"
  applicationsetcontroller.enable.leader.election: "true"
```
## Application Controller
Set the below env variables. This can be done on the command line or in the run configuration of an IDE
```shell
ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER=localhost:8090
ARGOCD_BINARY_NAME=argocd-application-controller
REDIS_SERVER=localhost:6379
ARGOCD_FAKE_IN_CLUSTER=true
```
Port forward the redis and repo server services.

**PLEASE BE CAREFUL AS THIS WILL USE YOUR DEFAULT KUBECONFIG!**
If you are also running the repo server locally, you can omit the forwarding.
```shell
kubectl port-forward service/argocd-redis 6379:6379 &> /dev/null &
kubectl port-forward service/argocd-repo-server 8090:8081 &> /dev/null &
```
Finally, scale down the application controller running in the cluster (or don't)
```shell
kubectl scale sts argocd-application-controller --replicas=0
```
## ApplicationSet Controller
Set the below env variables. This can be done on the command line or in the run configuration of an IDE
```shell
ARGOCD_BINARY_NAME=argocd-applicationset-controller
ARGOCD_APPLICATIONSET_CONTROLLER_REPO_SERVER=localhost:8090
ARGOCD_APPLICATIONSET_CONTROLLER_REPO_SERVER_PLAINTEXT=true
```
Add the following to your command line, you can pick any port.

`--metrics-addr :9999 --probe-addr :9998`
Port forward the repo server service.

**PLEASE BE CAREFUL AS THIS WILL USE YOUR DEFAULT KUBECONFIG!**
If you are also running the repo server locally, you can omit the forwarding.
```shell
kubectl port-forward service/argocd-repo-server 8090:8081 &> /dev/null &
```
## RepoServer
Set the below env variables. This can be done on the command line or in the run configuration of an IDE
```shell
ARGOCD_BINARY_NAME=argocd-repo-server
ARGOCD_GPG_ENABLED=false
ARGOCD_REPO_SERVER_DISABLE_TLS=true
REDIS_SERVER=localhost:6379
```
**PLEASE BE CAREFUL AS THIS WILL USE YOUR DEFAULT KUBECONFIG!**
Port forward the redis service.

```shell
kubectl port-forward service/argocd-redis 6379:6379 &> /dev/null &
```

##Troubleshooting
"A keychain cannot be found to store "<git repo>"
When running the Applicationset controller (specifically with Git Generators) or the RepoServer, the components will be interacting with your local Git configuration.
Specifically, if on Mac, it may try to store Git config in your keychain. To solve this, you need to temporarily unset your Git credential helper as follows below. NOTE - If the 1st command doesn't work, try alternative solutions listed below.

```shell
git config --system --unset credential.helper
git config --global --unset credential.helper
git config --local --unset credential.helper

# to reset
git config --system --add credential.helper osxkeychain
```
Manual Editing: git config --show-origin --get credential.helper
You can check if the credential helper was successfully removed via the following: 
```
git config --list | grep credential
```