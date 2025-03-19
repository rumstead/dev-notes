## Using the redis-cli
```shell
redis-cli --pass $REDIS_PASSWORD
```
### Running commands using the cli and decompressing
```shell
redis-cli --pass $REDIS_PASSWORD GET "app|resources-tree|raw-app|1.8.3.gz" | gunzip
```