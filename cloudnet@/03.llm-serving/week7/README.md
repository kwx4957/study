## LLM Serving 스터디 7주차

>

### 목차 
- [1. VM 생성을 위한 GCP VM 설정](#VM-생성을-위한-GCP-설정)
- [2. k3s 설치 및 gpu 설정](#k3s-설치-및-gpu-설정)
- [3. kube-promethues-stack 설치](#kube-promethues-stack)
- [4. Hami](#Hami)
- [5. Minio](#Minio)
- [6. vllm 배포](#vllm-배포)
- [7. llm-d](#llm-d)

### VM-생성을-위한-GCP-설정
```sh
brew update && brew install --cask gcloud-cli
gcloud init --console-only

export PROJECT_ID="$(gcloud config get-value project)"
export VM_NAME="lld-d"
export MACHINE_TYPE="g2-standard-4"
export IMAGE_FAMILY="rocky-linux-9-optimized-gcp"
export IMAGE_PROJECT="rocky-linux-cloud"
export DISK_SIZE=100

ZONES="$(gcloud compute machine-types list \
  --project="$PROJECT_ID" \
  --filter="name=$MACHINE_TYPE" \
  --format='value(zone)')"

for ZONE in $ZONES; do
  echo "Trying: $ZONE / $MACHINE_TYPE"

  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="${DISK_SIZE}GB" \
    --boot-disk-type=pd-balanced \
    --maintenance-policy=TERMINATE && exit 0

  echo "Failed: $ZONE / $MACHINE_TYPE"
done

export NETWORK=default
export MY_IP=$(curl -4 -s ifconfig.me)

# 내 IP에 대해서만 방화벽 개방 
# 30001 : 프로메테우스
# 30002 : 그라파나
# 30003 : minio 
gcloud compute firewall-rules create allow-workshop-my-ip \
--project="$PROJECT_ID" \
--network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22,tcp:30001,tcp:30002,tcp:30003,tcp:30004,tcp:30005 \
  --source-ranges="${MY_IP}/32"

gcloud compute ssh kwx4957@llm-d \
  --project="$PROJECT_ID" \
  --zone=asia-northeast3-a

sudo systemctl stop firewalld

sudo dnf install -y pciutils tree

lspci | grep -i nvidia 
00:03.0 3D controller: NVIDIA Corporation AD104GL [L4] (rev a1)

ls -l /dev/nvidia*
ls: cannot access '/dev/nvidia*': No such file or directory

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
```

### k3s 설치 및 gpu 설정

```sh
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --kube-controller-manager-arg=bind-address=0.0.0.0 \
  --kube-scheduler-arg=bind-address=0.0.0.0 \
  --kube-proxy-arg=metrics-bind-address=0.0.0.0 \
  --write-kubeconfig-mode=644

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl get node -owide
NAME    STATUS   ROLES           AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                         CONTAINER-RUNTIME
llm-d   Ready    control-plane   20s   v1.36.4+k3s1   10.178.0.3    <none>        Rocky Linux 9.8 (Blue Onyx)   5.14.0-687.44.1.el9_8.x86_64 (amd64)   containerd://2.3.4-k3s1.36

kubectl get pod -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   coredns-54996dc9b4-q4nbv                  1/1     Running   0          2m1s
kube-system   local-path-provisioner-77b9867795-sq4nw   1/1     Running   0          2m1s
kube-system   metrics-server-6dc596dfb8-njsx6           1/1     Running   0          2m1s

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Containerd 소켓 경로 문제로 실행이 되지 않기때문에, Containerd 경로 옵션 추가 필수 
helm upgrade --install gpu-operator \
  nvidia/gpu-operator \
  --namespace gpu-operator \
  --set 'toolkit.env[0].name=CONTAINERD_CONFIG' \
  --set 'toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml' \
  --set 'toolkit.env[1].name=CONTAINERD_SOCKET' \
  --set 'toolkit.env[1].value=/run/k3s/containerd/containerd.sock' \
  --set 'toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS' \
  --set 'toolkit.env[2].value=nvidia' \
  --set 'toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT' \
  --set-string 'toolkit.env[3].value=true'
  --set dcgmExporter.serviceMonitor.enabled=true \
  --set dcgmExporter.serviceMonitor.additionalLabels.release=kube-prometheus-stack
  --create-namespace

kubectl get pods -n gpu-operator
NAME                                                          READY   STATUS      RESTARTS      AGE
gpu-feature-discovery-9tdt7                                   1/1     Running     0             11m
gpu-operator-6cd4764cbf-bc5cx                                 1/1     Running     1 (34s ago)   12m
gpu-operator-node-feature-discovery-gc-7d4b864d68-llxt5       1/1     Running     0             12m
gpu-operator-node-feature-discovery-master-8649684bd6-fqfbk   1/1     Running     0             12m
gpu-operator-node-feature-discovery-worker-gcgxd              1/1     Running     0             12m
nvidia-container-toolkit-daemonset-gklsn                      1/1     Running     0             53s
nvidia-cuda-validator-fx2m6                                   0/1     Completed   0             25s
nvidia-dcgm-exporter-8992j                                    0/1     Running     0             11m
nvidia-device-plugin-daemonset-nsbbv                          1/1     Running     0             11m
nvidia-driver-daemonset-zh69m                                 1/1     Running     0             11m
nvidia-operator-validator-mxdnt                               1/1     Running     0             11m

kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
NAME    GPU
llm-d   1

kubectl get runtimeclass |grep nvidia*
nvidia                nvidia                34m
nvidia-cdi            nvidia-cdi            33m
nvidia-experimental   nvidia-experimental   34m
nvidia-legacy         nvidia-legacy         33m

kubectl describe node llm-d | grep -A7 Allocatable
Allocatable:
  cpu:                4
  ephemeral-storage:  81339450100
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             16107372Ki
  nvidia.com/gpu:     1
  pods:               110

kubectl get nodes -o json | jq -r '
  .items[] |
  .metadata.name as $node |
  .metadata.labels |
  to_entries[] |
  select(.key | startswith("nvidia.com/")) |
  "\($node)\t\(.key)=\(.value)"
'
llm-d   nvidia.com/cuda.driver-version.full=595.91.07
llm-d   nvidia.com/cuda.driver-version.major=595
llm-d   nvidia.com/cuda.driver-version.minor=91
llm-d   nvidia.com/cuda.driver-version.revision=07
llm-d   nvidia.com/cuda.driver.major=595
llm-d   nvidia.com/cuda.driver.minor=91
llm-d   nvidia.com/cuda.driver.rev=07
llm-d   nvidia.com/cuda.runtime-version.full=13.2
llm-d   nvidia.com/cuda.runtime-version.major=13
llm-d   nvidia.com/cuda.runtime-version.minor=2
llm-d   nvidia.com/cuda.runtime.major=13
llm-d   nvidia.com/cuda.runtime.minor=2
llm-d   nvidia.com/gfd.timestamp=1789843655
llm-d   nvidia.com/gpu-driver-upgrade-state=upgrade-done
llm-d   nvidia.com/gpu.compute.major=8
llm-d   nvidia.com/gpu.compute.minor=9
llm-d   nvidia.com/gpu.count=1
llm-d   nvidia.com/gpu.deploy.client=true
llm-d   nvidia.com/gpu.deploy.container-toolkit=true
llm-d   nvidia.com/gpu.deploy.dcgm=true
llm-d   nvidia.com/gpu.deploy.dcgm-exporter=true
llm-d   nvidia.com/gpu.deploy.device-plugin=true
llm-d   nvidia.com/gpu.deploy.driver=true
llm-d   nvidia.com/gpu.deploy.gpu-feature-discovery=true
llm-d   nvidia.com/gpu.deploy.node-status-exporter=true
llm-d   nvidia.com/gpu.deploy.nvsm=
llm-d   nvidia.com/gpu.deploy.operator-validator=true
llm-d   nvidia.com/gpu.family=ada-lovelace
llm-d   nvidia.com/gpu.machine=Google-Compute-Engine
llm-d   nvidia.com/gpu.memory=23034
llm-d   nvidia.com/gpu.mode=compute
llm-d   nvidia.com/gpu.present=true
llm-d   nvidia.com/gpu.product=NVIDIA-L4
llm-d   nvidia.com/gpu.replicas=1
llm-d   nvidia.com/gpu.sharing-strategy=none
llm-d   nvidia.com/mig.capable=false
llm-d   nvidia.com/mig.strategy=single
llm-d   nvidia.com/mps.capable=false
llm-d   nvidia.com/vgpu.present=false
```


### kube-promethues-stack
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

export MY_IP=$(curl -4 -s ifconfig.me)

cat <<EOT > monitor-values.yaml
prometheus:
  service:
    type: NodePort
    nodePort: 30001
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator
  service:
    type: NodePort
    nodePort: 30002
  persistence:
    enabled: true
    type: pvc
    storageClassName: local-path
    accessModes:
      - ReadWriteOnce
    size: 10Gi
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
prometheus-windows-exporter:
  prometheus:
    monitor:
      enabled: false
kubeControllerManager:
  enabled: true
  endpoints:
    - $MY_IP
  service:
    enabled: true
    port: 10257
    targetPort: 10257
  serviceMonitor:
    enabled: true
    https: true
    insecureSkipVerify: true
kubeScheduler:
  enabled: true
  endpoints:
    - $MY_IP
  service:
    enabled: true
    port: 10259
    targetPort: 10259
  serviceMonitor:
    enabled: true
    https: true
    insecureSkipVerify: true
kubeProxy:
  enabled: true
  endpoints:
    - $MY_IP
  service:
    enabled: true
    port: 10249
    targetPort: 10249
  serviceMonitor:
    enabled: true

kubeEtcd:
  enabled: false
EOT
cat monitor-values.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 87.5.1 \
-f monitor-values.yaml --create-namespace --namespace monitoring

helm list -n monitoring
NAME                    NAMESPACE       REVISION        UPDATED                                  STATUS          CHART                           APP VERSION
kube-prometheus-stack   monitoring      4               2026-09-19 19:01:16.619555402 +0000 UTC  deployed        kube-prometheus-stack-87.5.1    v0.92.1

kubectl get pod,svc,ingress -n monitoring
NAME                                                            READY   STATUS    RESTARTS   AGE
pod/alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          4m38s
pod/kube-prometheus-stack-grafana-ffb8dcc6b-kln7q               3/3     Running   0          4m44s
pod/kube-prometheus-stack-kube-state-metrics-5497db9c5c-zccxf   1/1     Running   0          4m44s
pod/kube-prometheus-stack-operator-869dcd685c-d2998             1/1     Running   0          4m44s
pod/kube-prometheus-stack-prometheus-node-exporter-lcwfs        1/1     Running   0          4m44s
pod/prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          4m37s

NAME                                                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                         AGE
service/alertmanager-operated                            ClusterIP   None            <none>        9093/TCP,9094/TCP,9094/UDP      4m38s
service/kube-prometheus-stack-alertmanager               ClusterIP   10.43.240.35    <none>        9093/TCP,8080/TCP               4m44s
service/kube-prometheus-stack-grafana                    NodePort    10.43.102.59    <none>        80:30002/TCP                    4m44s
service/kube-prometheus-stack-kube-state-metrics         ClusterIP   10.43.35.2      <none>        8080/TCP                        4m44s
service/kube-prometheus-stack-operator                   ClusterIP   10.43.205.90    <none>        443/TCP                         4m44s
service/kube-prometheus-stack-prometheus                 NodePort    10.43.55.196    <none>        9090:30001/TCP,8080:32271/TCP   4m44s
service/kube-prometheus-stack-prometheus-node-exporter   ClusterIP   10.43.184.141   <none>        9100/TCP                        4m44s
service/prometheus-operated                              ClusterIP   None            <none>        9090/TCP                        4m37s

kubectl get prometheus,servicemonitors,alertmanagers -n monitoring
NAME                                                            READY   STATUS    RESTARTS   AGE
pod/alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          4m38s
pod/kube-prometheus-stack-grafana-ffb8dcc6b-kln7q               3/3     Running   0          4m44s
pod/kube-prometheus-stack-kube-state-metrics-5497db9c5c-zccxf   1/1     Running   0          4m44s
pod/kube-prometheus-stack-operator-869dcd685c-d2998             1/1     Running   0          4m44s
pod/kube-prometheus-stack-prometheus-node-exporter-lcwfs        1/1     Running   0          4m44s
pod/prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          4m37s

NAME                                                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                         AGE
service/alertmanager-operated                            ClusterIP   None            <none>        9093/TCP,9094/TCP,9094/UDP      4m38s
service/kube-prometheus-stack-alertmanager               ClusterIP   10.43.240.35    <none>        9093/TCP,8080/TCP               4m44s
service/kube-prometheus-stack-grafana                    NodePort    10.43.102.59    <none>        80:30002/TCP                    4m44s
service/kube-prometheus-stack-kube-state-metrics         ClusterIP   10.43.35.2      <none>        8080/TCP                        4m44s
service/kube-prometheus-stack-operator                   ClusterIP   10.43.205.90    <none>        443/TCP                         4m44s
service/kube-prometheus-stack-prometheus                 NodePort    10.43.55.196    <none>        9090:30001/TCP,8080:32271/TCP   4m44s
service/kube-prometheus-stack-prometheus-node-exporter   ClusterIP   10.43.184.141   <none>        9100/TCP                        4m44s
service/prometheus-operated                              ClusterIP   None            <none>        9090/TCP                        4m37s

# prometheus
open http://$MY_IP:30001
# grafana : admin / prom-operator
open http://$MY_IP:30002

# 대쉬보드 구축 
curl -L \
  https://grafana.com/api/dashboards/12239/revisions/latest/download \
  -o dashboard-12239.json

curl -L \
  https://grafana.com/api/dashboards/23382/revisions/latest/download \
  -o dashboard-23382.json

# 기존 데이터소스 설정 불일치 문제 해결
PROMETHEUS_UID=prometheus
curl -fsSL \
  https://grafana.com/api/dashboards/12239/revisions/latest/download \
  -o dashboard-12239.raw.json

jq --arg uid "$PROMETHEUS_UID" '
  walk(
    if type == "string" then
      gsub("\\$\\{DS_PROMETHEUS\\}"; $uid)
    else
      .
    end
  )
  | del(.__inputs)
' dashboard-12239.raw.json > dashboard-12239.json

curl -fsSL \
  https://grafana.com/api/dashboards/23382/revisions/latest/download \
  -o dashboard-23382.raw.json

jq --arg uid "$PROMETHEUS_UID" '
  walk(
    if type == "string" then
      gsub("\\$\\{DS_PROMETHEUS\\}"; $uid)
    else
      .
    end
  )
  | del(.__inputs)
' dashboard-23382.raw.json > dashboard-23382.json

# json 그라파나 대쉬보드 반영
kubectl create configmap grafana-dashboard-dcgm-12239 \
  -n monitoring \
  --from-file=dcgm-exporter-dashboard.json=dashboard-12239.json \
  --dry-run=client -o yaml | kubectl label -f - --local -o yaml grafana_dashboard=1 | kubectl apply -f -
  
kubectl create configmap grafana-dashboard-dcgm-23382 \
  -n monitoring \
  --from-file=dcgm-k8s-dashboard.json=dashboard-23382.json \
  --dry-run=client -o yaml | kubectl label -f - --local -o yaml grafana_dashboard=1 | kubectl apply -f -

kubectl get configmap -n monitoring -l grafana_dashboard=1 |grep dcgm
grafana-dashboard-dcgm-12239                              1      35s
grafana-dashboard-dcgm-23382                              1      34s
```

### Hami

```sh
# 엔비디아 디바이스 플러그인 hami 충돌 방지를 위한 false 처리, 
helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --reuse-values \
  --set devicePlugin.enabled=false

# 노드 라벨링 추가
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label nodes ${NODE_NAME} gpu=on

helm repo add hami-charts https://project-hami.github.io/HAMi/
helm repo update

cat > hami-values.yaml <<'EOF'
devicePlugin:
  deviceListStrategy: cdi-annotations
  monitor:
    extraArgs:
    - -v=4
    - --metrics-bind-address=:9394
  # k3s의 경우 해당 설정 추가, 없으시 배포 실패 
  nvidiaDriverRoot: /run/nvidia/driver
  nvidiaHookPath: /usr/local/nvidia/toolkit/nvidia-ctk
  runtimeClassName: nvidia
  
prometheus:
  enabled: true # GPU Utilization Metrics  https://project-hami.io/docs/developers/gpu-utilization-metrics
  
scheduler:
  kubeScheduler:
    imageTag: v1.36.4
EOF

helm install hami hami-charts/hami -n kube-system --version 2.10.0 -f hami-values.yaml

helm get values -n kube-system hami
USER-SUPPLIED VALUES:
devicePlugin:
  deviceListStrategy: cdi-annotations
  monitor:
    extraArgs:
    - -v=4
    - --metrics-bind-address=:9394
  nvidiaDriverRoot: /run/nvidia/driver
  nvidiaHookPath: /usr/local/nvidia/toolkit/nvidia-ctk
  runtimeClassName: nvidia
prometheus:
  enabled: true
scheduler:
  kubeScheduler:
    imageTag: v1.36.4

curl -fsSLo hami-vgpu-dashboard.json \
  https://project-hami.io/assets/files/gpu-dashboard-1f1ee85b9fb124c57657b807e42d0f0b.json

# 하미 그라파나 대쉬보드 생성
kubectl create configmap grafana-dashboard-hami-vgpu \
  --namespace monitoring \
  --from-file=hami-vgpu-dashboard.json=hami-vgpu-dashboard.json \
  --dry-run=client \
  -o yaml \
| kubectl label -f - --local -o yaml grafana_dashboard=1 \
| kubectl apply -f -
```

### Minio
```sh
kubectl create namespace vllm

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: vllm
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 30Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: vllm
type: Opaque
stringData:
  MINIO_ROOT_USER: admin
  MINIO_ROOT_PASSWORD: superadmin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
        - name: minio
          image: quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          envFrom:
            - secretRef:
                name: minio-credentials
          ports:
            - name: api
              containerPort: 9000
            - name: console
              containerPort: 9001
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minio-data
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: vllm
spec:
  selector:
    app: minio
  ports:
    - name: api
      port: 9000
      targetPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: vllm
spec:
  type: NodePort
  selector:
    app: minio
  ports:
    - name: console
      port: 9001
      targetPort: 9001
      nodePort: 30003
EOF

kubectl  get pod -n vllm
NAME                    READY   STATUS    RESTARTS       AGE
minio-9c47675d7-fttcx   1/1     Running   5 (110s ago)   3m28s

# model 캐시
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: model-loader
  namespace: vllm
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: hf-download
          image: python:3.12-slim
          command:
            - sh
            - -c
            - |
              set -eu
              pip install --no-cache-dir -U "huggingface_hub[cli]"
              hf download Qwen/Qwen3-0.6B-FP8 \
                --local-dir /model
          volumeMounts:
            - name: model
              mountPath: /model
      containers:
        - name: s3-upload
          image: quay.io/minio/mc:latest
          command:
            - sh
            - -c
            - |
              set -eu
              mc alias set localminio http://minio.vllm.svc.cluster.local:9000 \
                "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing localminio/models
              mc mirror --overwrite /model localminio/models/Qwen3-0.6B-FP8
          envFrom:
            - secretRef: { name: minio-credentials }
          volumeMounts:
            - name: model
              mountPath: /model
      volumes:
        - name: model
          emptyDir:
            sizeLimit: 5Gi
EOF

kubectl get job -n vllm
NAME           STATUS     COMPLETIONS   DURATION   AGE
model-loader   Complete   1/1           42s        68s
```


### vLLM 배포
```sh
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen3-0-6b-fp8
  namespace: vllm
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels: { app: qwen3-0-6b-fp8 }
  template:
    metadata:
      labels: { app: qwen3-0-6b-fp8 }
    spec:
      schedulerName: hami-scheduler
      runtimeClassName: nvidia
      containers:
        - name: vllm
          image: docker.io/vllm/vllm-openai:v0.28.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              python3 -c "import runai_model_streamer" 2>/dev/null || pip install --no-cache-dir vllm[runai]
              exec vllm serve s3://models/Qwen3-0.6B-FP8 \
                --served-model-name Qwen3-0.6B-FP8 \
                --load-format runai_streamer \
                --host 0.0.0.0 --port 8000 \
                --max-model-len 8192
          env:
            - name: AWS_ENDPOINT_URL
              value: "http://minio.vllm.svc.cluster.local:9000"
            - name: AWS_EC2_METADATA_DISABLED
              value: "true"
            - name: RUNAI_STREAMER_S3_USE_VIRTUAL_ADDRESSING
              value: "0"
            - name: AWS_DEFAULT_REGION
              value: "us-east-1"
            - name: AWS_ACCESS_KEY_ID
              valueFrom: { secretKeyRef: { name: minio-credentials, key: MINIO_ROOT_USER } }
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom: { secretKeyRef: { name: minio-credentials, key: MINIO_ROOT_PASSWORD } }
            - name: VLLM_CACHE_ROOT
              value: /vllm-cache
          ports:
            - containerPort: 8000
              name: http
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              cpu: "1"
              memory: 2Gi
          readinessProbe:
            httpGet: { path: /health, port: 8000 }
            initialDelaySeconds: 30
            periodSeconds: 10
          volumeMounts:
            - name: vllm-cache
              mountPath: /vllm-cache
      volumes:
        - name: vllm-cache
          hostPath:
            path: /var/cache/vllm
            type: DirectoryOrCreate
---
apiVersion: v1
kind: Service
metadata:
  name: qwen3-0-6b-fp8
  namespace: vllm
spec:
  type: NodePort
  selector: { app: qwen3-0-6b-fp8 }
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30004
EOF

tree /var/cache/vllm/ -L 4
/var/cache/vllm/
├── modelinfos
│   └── vllm-model_executor-models-qwen3-Qwen3ForCausalLM.json
└── torch_compile_cache
    ├── a9b21c3b8b
    │   └── rank_0_0
    │       └── backbone
    └── torch_aot_compile
        └── 123b9c7a77465a2b56029e6119d1d05a6b1d587ae900bc2e70173ec5fd7a6d9e
            ├── inductor_cache
            └── rank_0_0
            

kubectl get deploy,svc,ep -n vllm qwen3-0-6b-fp8
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/qwen3-0-6b-fp8   1/1     1            1           17m

NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/qwen3-0-6b-fp8   NodePort   10.43.176.105   <none>        8000:30004/TCP   30m

NAME                       ENDPOINTS         AGE
endpoints/qwen3-0-6b-fp8   10.42.0.49:8000   30m


curl -sO https://raw.githubusercontent.com/vllm-project/vllm/main/examples/observability/dashboards/grafana/performance_statistics.json
curl -sO https://raw.githubusercontent.com/vllm-project/vllm/main/examples/observability/dashboards/grafana/query_statistics.json

kubectl label svc qwen3-0-6b-fp8 -n vllm app=qwen3-0-6b-fp8 --overwrite

kubectl patch svc qwen3-0-6b-fp8 -n vllm --type=json \
  -p='[{"op":"add","path":"/spec/ports/0/name","value":"http"}]'

cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-qwen3-0-6b-fp8
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
    - vllm
  selector:
    matchLabels:
      app: qwen3-0-6b-fp8
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
EOF

kubectl create configmap grafana-dashboard-vllm-performance \
  --namespace monitoring \
  --from-file=performance_statistics.json \
  --dry-run=client \
  -o yaml \
| kubectl label -f - --local -o yaml grafana_dashboard=1 \
| kubectl apply -f -

kubectl create configmap grafana-dashboard-query-statistics \
  --namespace monitoring \
  --from-file=query_statistics.json \
  --dry-run=client \
  -o yaml \
| kubectl label -f - --local -o yaml grafana_dashboard=1 \
| kubectl apply -f -

curl -s http://${MY_IP}:30001/api/v1/targets | \
  jq '.data.activeTargets[] | select(.scrapePool|test("vllm")) | {scrapePool, health, scrapeUrl}'
{
  "scrapePool": "serviceMonitor/monitoring/vllm-qwen3-0-6b-fp8/0",
  "health": "up",
  "scrapeUrl": "http://10.42.0.49:8000/metrics"
}

curl -sG "http://${MY_IP}:30001/api/v1/query" \
>   --data-urlencode 'query=vllm:num_requests_running' \
> | jq .
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "vllm:num_requests_running",
          "container": "vllm",
          "endpoint": "http",
          "engine": "0",
          "instance": "10.42.0.49:8000",
          "job": "qwen3-0-6b-fp8",
          "model_name": "Qwen3-0.6B-FP8",
          "namespace": "vllm",
          "pod": "qwen3-0-6b-fp8-9dc6bf7c5-4jkt4",
          "service": "qwen3-0-6b-fp8"
        },
        "value": [
          1789849813.895,
          "0"
        ]
      }
    ]
  }
}

# Grafana 대시보드 확인
# admin / prom-operator
open http://$MY_IP:30002

curl -s http://${MY_IP}:30004/v1/models | python3 -m json.tool
{
    "object": "list",
    "data": [
        {
            "id": "Qwen3-0.6B-FP8",
            "object": "model",
            "created": 1789853888,
            "owned_by": "vllm",
            "root": "s3://models/Qwen3-0.6B-FP8",
            "parent": null,
            "max_model_len": 8192,
            "permission": [
                {
                    "id": "modelperm-8913cb9901ba7284",
                    "object": "model_permission",
                    "created": 1789853888,
                    "allow_create_engine": false,
                    "allow_sampling": true,
                    "allow_logprobs": true,
                    "allow_search_indices": false,
                    "allow_view": true,
                    "allow_fine_tuning": false,
                    "organization": "*",
                    "group": null,
                    "is_blocking": false
                }
            ]
        }
    ]
}

# output
curl -s http://${MY_IP}:30004/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-0.6B-FP8",
    "messages": [
      {"role": "user", "content": "한국의 수도는 어디야?"}
    ],
    "max_tokens": 50
  }' | jq .choices
 [
  {
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "<think>\nOkay, the user is asking about the capital of South Korea. Let me start by recalling that South Korea's capital is Seoul, right? I think it's the capital city. Now, I need to make sure I don't mix up",
      "refusal": null,
      "annotations": null,
      "audio": null,
      "function_call": null,
      "reasoning": null
    },
    "logprobs": null,
    "finish_reason": "length",
    "stop_reason": null,
    "token_ids": null,
    "routed_experts": null
  }
]
```

### llm-d
```sh
# gateway-api 배포
kubectl apply --server-side=true -f \
  https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.2/manifests.yaml

# envoy-gateway 배포
helm upgrade --install envoy-gateway \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.9.1 \
  --namespace envoy-gateway-system \
  --create-namespace \
  --skip-crds

# ai gateway crd 배포
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v1.1.0 -n envoy-ai-gateway-system --create-namespace

# ai gateway 배포 
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v1.1.0 -n envoy-ai-gateway-system --create-namespace
  
kubectl apply -f \
  https://raw.githubusercontent.com/theagentrouter/agent-router/main/examples/inference-pool/base.yaml

kubectl apply -f \
  https://raw.githubusercontent.com/theagentrouter/agent-router/main/examples/inference-pool/aigwroute.yaml

kubectl rollout restart -n envoy-gateway-system deployment/envoy-gateway

kubectl get pods -n envoy-ai-gateway-system
NAME                                     READY   STATUS    RESTARTS   AGE
ai-gateway-controller-59899b6864-fgzm6   1/1     Running   0          67s

kubectl get pods -n envoy-gateway-system
NAME                                                              READY   STATUS    RESTARTS   AGE
envoy-default-inference-pool-with-aigwroute-d416582c-7889fmnknn   3/3     Running   0          50s
envoy-gateway-8d45c6b4f-cdqqj                                     1/1     Running   0          46s

kubectl get crd inferencepools.inference.networking.x-k8s.io
NAME                                           CREATED AT
inferencepools.inference.networking.x-k8s.io   2026-09-19T20:46:54Z

kubectl get deploy,pod -n envoy-gateway-system -l app.kubernetes.io/component=proxy -owide
NAME                                                                   READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS               IMAGES                                                                                                                                                      SELECTOR
deployment.apps/envoy-default-inference-pool-with-aigwroute-d416582c   1/1     1            1           61m   envoy,shutdown-manager   docker.io/envoyproxy/envoy:distroless-v1.39.1@sha256:eb2c01c13125d1629637cb4e4cce7207009fb7cc2c8027f9742758549d15b6f4,docker.io/envoyproxy/gateway:v1.9.1   app.kubernetes.io/component=proxy,app.kubernetes.io/managed-by=envoy-gateway,app.kubernetes.io/name=envoy,gateway.envoyproxy.io/owning-gateway-name=inference-pool-with-aigwroute,gateway.envoyproxy.io/owning-gateway-namespace=default
NAME                                                                  READY   STATUS    RESTARTS   AGE   IP           NODE    NOMINATED NODE   READINESS GATES
pod/envoy-default-inference-pool-with-aigwroute-d416582c-7889fmnknn   3/3     Running   0          60m   10.42.0.64   llm-d   <none>           <none>


kubectl get svc,ep -n envoy-gateway-system -l app.kubernetes.io/component=proxy
NAME                                                           TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/envoy-default-inference-pool-with-aigwroute-d416582c   LoadBalancer   10.43.51.113   10.178.0.3    80:32067/TCP   61m
NAME                                                             ENDPOINTS          AGE
endpoints/envoy-default-inference-pool-with-aigwroute-d416582c   10.42.0.64:10080   61m


# EPP 배포
cat <<'EOF' | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: qwen3-router-epp
  namespace: vllm
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: qwen3-router-epp-read
  namespace: vllm
rules:
  # Stable InferencePool API used by qwen3-router
  - apiGroups:
      - inference.networking.k8s.io
    resources:
      - inferencepools
    verbs:
      - get
      - list
      - watch

  # Inference Extension API watched by EPP
  - apiGroups:
      - inference.networking.x-k8s.io
    resources:
      - inferenceobjectives
      - inferencepools
    verbs:
      - get
      - list
      - watch

  # EPP discovers Ready Qwen Pods using the Pool selector
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: qwen3-router-epp-read
  namespace: vllm
subjects:
  - kind: ServiceAccount
    name: qwen3-router-epp
    namespace: vllm
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: qwen3-router-epp-read
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: qwen3-router-epp-config
  namespace: vllm
data:
  default-plugins.yaml: |
    apiVersion: inference.networking.x-k8s.io/v1alpha1
    kind: EndpointPickerConfig
    plugins:
      - type: queue-scorer
    schedulingProfiles:
      - name: default
        plugins:
          - pluginRef: queue-scorer
---
apiVersion: v1
kind: Service
metadata:
  name: qwen3-router-epp
  namespace: vllm
spec:
  type: ClusterIP
  selector:
    app: qwen3-router-epp
  ports:
    - name: grpc
      port: 9002
      targetPort: grpc
      appProtocol: kubernetes.io/h2c
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen3-router-epp
  namespace: vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qwen3-router-epp
  template:
    metadata:
      labels:
        app: qwen3-router-epp
    spec:
      serviceAccountName: qwen3-router-epp
      terminationGracePeriodSeconds: 130
      containers:
        - name: epp
          image: registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1
          imagePullPolicy: IfNotPresent
          args:
            - --pool-name
            - qwen3-router
            - --pool-namespace
            - vllm
            - --v
            - "4"
            - --zap-encoder
            - json
            - --grpc-port
            - "9002"
            - --grpc-health-port
            - "9003"
            - --config-file
            - /config/default-plugins.yaml
          ports:
            - name: grpc
              containerPort: 9002
            - name: grpc-health
              containerPort: 9003
            - name: metrics
              containerPort: 9090
          readinessProbe:
            grpc:
              port: 9003
              service: inference-extension
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            grpc:
              port: 9003
              service: inference-extension
            initialDelaySeconds: 5
            periodSeconds: 10
          volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: qwen3-router-epp-config
---
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: qwen3-router
  namespace: vllm
spec:
  targetPorts:
    - number: 8000
  selector:
    matchLabels:
      app: qwen3-0-6b-fp8
  endpointPickerRef:
    name: qwen3-router-epp
    port:
      number: 9002
EOF


# inferencepool 조회
kubectl get inferencepool -n vllm qwen3-router
NAME           AGE
qwen3-router   52m

# inferencepool 설정 
kubectl get inferencepool -n vllm qwen3-router -o yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  annotations:
spec:
  endpointPickerRef:
    failureMode: FailClose
    group: ""
    kind: Service
    name: qwen3-router-epp
    port:
      number: 9002
  selector:
    matchLabels:
      app: qwen3-0-6b-fp8
  targetPorts:
  - number: 8000
status: {}


kubectl get svc,ep -n vllm -l app=qwen3-0-6b-fp8
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/qwen3-0-6b-fp8   NodePort   10.43.176.105   <none>        8000:30004/TCP   67m
NAME                       ENDPOINTS         AGE
endpoints/qwen3-0-6b-fp8   10.42.0.66:8000   67m


kubectl get deploy -n vllm qwen3-router-epp -owide
NAME               READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                                       SELECTOR
qwen3-router-epp   1/1     1            1           11m   epp          registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1   app=qwen3-router-epp


kubectl describe deploy -n vllm qwen3-router-epp
ame:                   qwen3-router-epp
Namespace:              vllm
CreationTimestamp:      Sat, 19 Sep 2026 20:50:30 +0000
Labels:                 <none>
Annotations:            deployment.kubernetes.io/revision: 4
Selector:               app=qwen3-router-epp
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:           app=qwen3-router-epp
  Annotations:      kubectl.kubernetes.io/restartedAt: 2026-09-19T20:58:40Z
  Service Account:  qwen3-router-epp
  Containers:
   epp:
    Image:       registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1
    Ports:       9002/TCP (grpc), 9003/TCP (grpc-health), 9090/TCP (metrics)
    Host Ports:  0/TCP (grpc), 0/TCP (grpc-health), 0/TCP (metrics)
    Args:
      --pool-name
      qwen3-router
      --pool-namespace
      vllm
      --v
      4
      --zap-encoder
      json
      --grpc-port
      9002
      --grpc-health-port
      9003
      --config-file
      /config/default-plugins.yaml
    Environment:  <none>
    Mounts:
      /config from config (rw)
  Volumes:
   config:
    Type:          ConfigMap (a volume populated by a ConfigMap)
    Name:          qwen3-router-epp-config
    Optional:      false
  Node-Selectors:  <none>
  Tolerations:     <none>
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  qwen3-router-epp-64498d85c4 (0/0 replicas created), qwen3-router-epp-5787f59467 (0/0 replicas created), qwen3-router-epp-849c58985c (0/0 replicas created)
NewReplicaSet:   qwen3-router-epp-86f588c844 (1/1 replicas created)


kubectl get cm -n vllm qwen3-router-epp -o yaml
apiVersion: v1
data:
  default-plugins.yaml: |
    apiVersion: inference.networking.x-k8s.io/v1alpha1
    kind: EndpointPickerConfig
    plugins:
      - type: queue-scorer
    schedulingProfiles:
      - name: default
        plugins:
          - pluginRef: queue-scorer
kind: ConfigMap
metadata:
  annotations:
  name: qwen3-router-epp-config
  namespace: vllm

kubectl logs -n vllm -l app=qwen3-router-epp -f
{"level":"Level(-4)","ts":"2026-09-19T21:52:23Z","logger":"controller-runtime.cache","caller":"cache/reflector.go:946","msg":"Watch close","reflector":"pkg/mod/k8s.io/client-go@v0.33.4/tools/cache/reflector.go:285","type":"*v1alpha2.InferenceObjective","totalItems":8}


cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-qwen3-router-from-default
  namespace: vllm
spec:
  from:
    - group: aigateway.envoyproxy.io
      kind: AIGatewayRoute
      namespace: default
  to:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: qwen3-router
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIGatewayRoute
metadata:
  name: qwen3-router
  namespace: default
spec:
  parentRefs:
    - name: inference-pool-with-aigwroute
      namespace: default
      group: gateway.networking.k8s.io
      kind: Gateway
  rules:
    - matches:
        - headers:
            - type: Exact
              name: x-ai-eg-model
              value: Qwen3-0.6B-FP8
      backendRefs:
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: qwen3-router
          namespace: vllm
EOF

kubectl get gateway
NAME                            CLASS                           ADDRESS      PROGRAMMED   AGE
inference-pool-with-aigwroute   inference-pool-with-aigwroute   10.178.0.3   True         78m

kubectl get aigatewayroute qwen3-router -n default -o yaml
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIGatewayRoute
metadata:
  name: qwen3-router
  namespace: default
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: inference-pool-with-aigwroute
    namespace: default
  rules:
  - backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: qwen3-router
      namespace: vllm
      priority: 0
      weight: 1
    matches:
    - headers:
      - name: x-ai-eg-model
        type: Exact
        value: Qwen3-0.6B-FP8
    modelsOwnedBy: Envoy AI Gateway

kubectl describe aigatewayroute qwen3-router -n default
Name:         qwen3-router
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  aigateway.envoyproxy.io/v1beta1
Kind:         AIGatewayRoute
Spec:
  Parent Refs:
    Group:      gateway.networking.k8s.io
    Kind:       Gateway
    Name:       inference-pool-with-aigwroute
    Namespace:  default
  Rules:
    Backend Refs:
      Group:      inference.networking.k8s.io
      Kind:       InferencePool
      Name:       qwen3-router
      Namespace:  vllm
      Priority:   0
      Weight:     1
    Matches:
      Headers:
        Name:         x-ai-eg-model
        Type:         Exact
        Value:        Qwen3-0.6B-FP8
    Models Owned By:  Envoy AI Gateway
Events:               <none>

kubectl get gateway inference-pool-with-aigwroute -n default
NAME                            CLASS                           ADDRESS      PROGRAMMED   AGE
inference-pool-with-aigwroute   inference-pool-with-aigwroute   10.178.0.3   True         78m

curl -sS --max-time 90 \
>   "http://${MY_IP}:30004/v1/chat/completions" \
>   -H 'Content-Type: application/json' \
>   -H 'x-ai-eg-model: Qwen3-0.6B-FP8' \
>   -d '{
>     "model": "Qwen3-0.6B-FP8",
>     "messages": [
>       {
>         "role": "user",
>         "content": "한국의 수도는 어디야?"
>       }
>     ],
>     "max_tokens": 50
>   }' | jq .
{
  "id": "chatcmpl-b75a0015b4f99fe9",
  "object": "chat.completion",
  "created": 1789855299,
  "model": "Qwen3-0.6B-FP8",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "<think>\nOkay, the user is asking where the capital of South Korea is. First, I need to confirm the correct answer. South Korea's capital is Seattle. That's where the Seoul capital would be in a country. I should mention the country",
        "refusal": null,
        "annotations": null,
        "audio": null,
        "function_call": null,
        "reasoning": null
      },
      "logprobs": null,
      "finish_reason": "length",
      "stop_reason": null,
      "token_ids": null,
      "routed_experts": null
    }
  ],
  "service_tier": null,
  "system_fingerprint": "vllm-0.28.0-dd5bf5d6",
  "usage": {
    "prompt_tokens": 16,
    "total_tokens": 66,
    "completion_tokens": 50,
    "prompt_tokens_details": null,
    "completion_tokens_details": null
  },
  "prompt_logprobs": null,
  "prompt_token_ids": null,
  "prompt_text": null,
  "kv_transfer_params": null,
  "ec_transfer_params": null,
  "metrics": null
}

```
