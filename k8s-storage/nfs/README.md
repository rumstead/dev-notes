docker run -d -p 2049:2049 --name nfs --privileged -v /Users/rumstead/tmp/pod-volume-test:/ -e SHARED_DIRECTORY=/nfsshare itsthenetwork/nfs-server-alpine:latest-arm