## 1. Dynamic exporter configuration (hubble flow logs) 로 파일 출력 후 해당 파일을 수집하여 볼 수 있는 로깅 시스템 구성해보기(미완)

구성 과정
1. 로그 수집을 위한 otel-col 배포
2. loki 배포 

## Otel collector 배포
```sh
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install my-opentelemetry-collector open-telemetry/opentelemetry-collector \
   --set image.repository="otel/opentelemetry-collector-k8s" \
   --set mode=daemonset 
```
https://opentelemetry.io/docs/platforms/kubernetes/helm/collector/


## Grafana Loki 배포
```sh
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 로키 배포
helm install loki grafana/loki -f values.yaml -n loki --create-namespace

# 설정 업그레이드 시 
helm upgrade loki grafana/loki -n loki -f values.yaml

kubectl get pods -n loki

helm uninstall loki -n loki

```

**loki-values.yaml**
```yaml
loki:
  
# This is a complete configuration to deploy Loki backed by the filesystem.
# The index will be shipped to the storage via tsdb-shipper.
  storage:
    tpye: filesystem
  auth_enabled: false

  server:
    http_listen_port: 3100

  common:
    ring:
      instance_addr: 127.0.0.1
      kvstore:
        store: inmemory
    replication_factor: 1
    path_prefix: /tmp/loki

  schema_config:
    configs:
    - from: 2020-05-15
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

  storage_config:
    filesystem:
      directory: /tmp/loki/chunks
```

**storage-class.yaml**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-loki-0
  namespace: loki
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: export-1-loki-minio-0
  namespace: loki
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 10Gi
```

https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/
