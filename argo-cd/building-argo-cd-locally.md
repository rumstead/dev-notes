# Building Argo CD Locally
## Building a binary
```shell
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
 GODEBUG="tarinsecurepath=0,zipinsecurepath=0" \
 go build -v -ldflags '-X github.com/argoproj/argo-cd/v2/common.version=2.14.0
 -X github.com/argoproj/argo-cd/v2/common.buildDate=2025-01-03T16:06:00Z
 -X github.com/argoproj/argo-cd/v2/common.gitCommit=4a99ef3b872fc93e91384bbb507221d7d9e63b7d 
 -X github.com/argoproj/argo-cd/v2/common.gitTreeState=dirty 
 -X github.com/argoproj/argo-cd/v2/common.kubectlVersion=v0.31.0 
 -X "github.com/argoproj/argo-cd/v2/common.extraBuildInfo=" 
 -extldflags "-static"' \
 -o /Users/rumstead/.gvm/pkgsets/go1.19.9/global/argo-cd/dist/argocd ./cmd
```
## Building the UI
```shell
yarn install
TARGET_PLATFORM=linux HOST_ARCH=amd64 NODE_ENV=production NODE_ONLINE_ENV='online' NODE_OPTIONS=--max_old_space_size=8192 yarn build
```

## Building the Docker image
```shell
docker build --progress=plain --build-arg HTTP_PROXY=$HTTP_PROXY --build-arg NO_PROXY=$NO_PROXY \ 
--build-arg CORP_CA_URL=$CORP_CA_URL \ 
-f Dockerfile.rumstead . -t "argo-cd:rumstead"
```
Remember to look at the `.dockerignore` for adding things from `./dist`