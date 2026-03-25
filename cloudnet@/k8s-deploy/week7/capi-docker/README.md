## Cluster API [^1]
> Cloudnet@ k8s Deploy 7주차 스터디를 진행하며 정리한 글입니다.

Cluster API란 k8s 클러스터를 프로비저닝, 업그레이드 및 운영하기 위한 선언적 API 및 도구를 제공하는 k8s 하위 프로젝트이다. CRD를 이용해 cluster api 자원을 정의하고 관리하며 k8s를 k8s으로 배포 및 관리한다.

구성 요소
- Management Cluster
- Workload Cluster
- Infrastructure Provider

```sh
# 해당 실습에서는 docker를 infra provider로 구성하여 실습한다.
docker context ls
NAME              DESCRIPTION                               DOCKER ENDPOINT                            ERROR
default           Current DOCKER_HOST based configuration   unix:///var/run/docker.sock 

# 미삭제 컨테이너 확인
docker ps -a

# management cluster kind를 통한 구성
kind create cluster --name myk8s --image kindest/node:v1.35.0 --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
  extraPortMappings:
  # sample app
  - containerPort: 30000     
    hostPort: 30000
  # kube-ops-view
  - containerPort: 30001     
    hostPort: 30001
EOF

# kube-ops-view 배포
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/
helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 \
  --set service.main.type=NodePort,service.main.ports.http.nodePort=30001 \
  --set env.TZ="Asia/Seoul" --namespace kube-system

open "http://127.0.0.1:30001/#scale=1.5"

# 1. mac 사용자
brew install clusterctl  

# 2. wsl 사용자
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.12.2/clusterctl-linux-amd64 -o clusterctl
sudo install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl

# clusterctl 버전 확인
clusterctl version -o json | jq
  "clusterctl": {
    "major": "1",
    "minor": "12",
    "gitVersion": "v1.12.3",
    "gitCommit": "Homebrew",
    "gitTreeState": "clean",
    "buildDate": "2026-02-17T10:43:04Z",
    "goVersion": "go1.26.0",
    "compiler": "gc",
    "platform": "darwin/arm64"
}

# docker를 infra provider로 지정, 이 경우 개발 환경 전용
# ClusterTopology 및 clusterclass 기능 지원 활성화
# ClusterClass는 cluster를 생성하기 위한 설계도 개념, 객체로 볼수 있다. 실제 클러스터가 생성된다면 객체 인스턴스
# ClusterTopology는 어떤 ClusterClass를 사용하고 어떤 변수를 삽입할지 정의한다.
export CLUSTER_TOPOLOGY=true 
clusterctl init --infrastructure docker

# 파드 확인
# capi 와 cert-manager 파드 확인
k get pods  -A
NAMESPACE                           NAME                                                             READY   STATUS              RESTARTS   AGE
capd-system                         capd-controller-manager-54755cdd6-cqjft                          0/1     ContainerCreating   0          16s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-controller-manager-94d8964d9-446v2        1/1     Running             0          17s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-controller-manager-6796744c76-hsdw6   1/1     Running             0          17s
capi-system                         capi-controller-manager-59c5798655-rb8gr                         1/1     Running             0          17s
cert-manager                        cert-manager-845844dd8-8vdx9                                     1/1     Running             0          33s
cert-manager                        cert-manager-cainjector-7b5d65fbcb-vc2nz                         1/1     Running             0          33s
cert-manager                        cert-manager-webhook-6fcf4cb6c-772kf                             1/1     Running             0          33s
kube-system                         coredns-7d764666f9-7rr2b                                         1/1     Running             0          7m59s
kube-system                         coredns-7d764666f9-m8j22                                         1/1     Running             0          7m59s
kube-system                         etcd-myk8s-control-plane                                         1/1     Running             0          8m8s
kube-system                         kindnet-v9vc2                                                    1/1     Running             0          7m59s
kube-system                         kube-apiserver-myk8s-control-plane                               1/1     Running             0          8m8s
kube-system                         kube-controller-manager-myk8s-control-plane                      1/1     Running             0          8m7s
kube-system                         kube-ops-view-5c64986f74-dqz9j                                   1/1     Running             0          6m10s
kube-system                         kube-proxy-crs5w                                                 1/1     Running             0          7m59s
kube-system                         kube-scheduler-myk8s-control-plane                               1/1     Running             0          8m8s
local-path-storage                  local-path-provisioner-67b8995b4b-wfwcb                          1/1     Running             0          7m59s

# crd 확인
# 처음보는 crd들이 대거 생성되엇다.
kubectl get crd
kubectl get crd | grep x-k8s
clusterclasses.cluster.x-k8s.io                              2026-02-18T05:13:38Z
clusterresourcesetbindings.addons.cluster.x-k8s.io           2026-02-18T05:13:38Z
clusterresourcesets.addons.cluster.x-k8s.io                  2026-02-18T05:13:38Z
clusters.cluster.x-k8s.io                                    2026-02-18T05:13:38Z
devclusters.infrastructure.cluster.x-k8s.io                  2026-02-18T05:13:39Z
devclustertemplates.infrastructure.cluster.x-k8s.io          2026-02-18T05:13:40Z
devmachines.infrastructure.cluster.x-k8s.io                  2026-02-18T05:13:40Z
devmachinetemplates.infrastructure.cluster.x-k8s.io          2026-02-18T05:13:40Z
dockerclusters.infrastructure.cluster.x-k8s.io               2026-02-18T05:13:40Z
dockerclustertemplates.infrastructure.cluster.x-k8s.io       2026-02-18T05:13:40Z
dockermachinepools.infrastructure.cluster.x-k8s.io           2026-02-18T05:13:40Z
dockermachinepooltemplates.infrastructure.cluster.x-k8s.io   2026-02-18T05:13:40Z
dockermachines.infrastructure.cluster.x-k8s.io               2026-02-18T05:13:40Z
dockermachinetemplates.infrastructure.cluster.x-k8s.io       2026-02-18T05:13:40Z
extensionconfigs.runtime.cluster.x-k8s.io                    2026-02-18T05:13:38Z
ipaddressclaims.ipam.cluster.x-k8s.io                        2026-02-18T05:13:38Z
ipaddresses.ipam.cluster.x-k8s.io                            2026-02-18T05:13:38Z
kubeadmconfigs.bootstrap.cluster.x-k8s.io                    2026-02-18T05:13:39Z
kubeadmconfigtemplates.bootstrap.cluster.x-k8s.io            2026-02-18T05:13:39Z
kubeadmcontrolplanes.controlplane.cluster.x-k8s.io           2026-02-18T05:13:39Z
kubeadmcontrolplanetemplates.controlplane.cluster.x-k8s.io   2026-02-18T05:13:39Z
machinedeployments.cluster.x-k8s.io                          2026-02-18T05:13:38Z
machinedrainrules.cluster.x-k8s.io                           2026-02-18T05:13:38Z
machinehealthchecks.cluster.x-k8s.io                         2026-02-18T05:13:38Z
machinepools.cluster.x-k8s.io                                2026-02-18T05:13:38Z
machines.cluster.x-k8s.io                                    2026-02-18T05:13:38Z
machinesets.cluster.x-k8s.io                                 2026-02-18T05:13:38Z
providers.clusterctl.cluster.x-k8s.io                        2026-02-18T05:13:14Z


# capi관련 피처 게이트 확인, ClusterTopology 및 InPlaceUpdates
kubectl describe -n capi-system deployment.apps/capi-controller-manager | grep feature-gates
      --feature-gates=MachinePool=true,ClusterTopology=true,RuntimeSDK=false,MachineSetPreflightChecks=true,MachineWaitForVolumeDetachConsiderVolumeAttachments=true,PriorityQueue=false,ReconcilerRateLimiting=false,InPlaceUpdates=false,MachineTaintPropagation=false
```

```mermaid
graph TD
    %% 프로바이더 노드
    Core[Core Provider<br/><b>Cluster API</b>]
    Infra[Infrastructure Provider<br/><b>CAPD : Docker</b>]
    Boot[Bootstrap Provider<br/><b>Kubeadm</b>]
    CP[Control Plane Provider<br/><b>Kubeadm</b>]

    %% 클러스터 생성 흐름
    Core -->|1. 정의 및 조정| CP
    CP -->|2. 설정 요청| Boot
    CP -->|3. 인프라 요청| Infra
    
    subgraph "Target Cluster 생성"
        Node[Docker Container<br/>as K8s Node]
    end

    Infra -->|실제 리소스 생성| Node
    Boot -->|Cloud-init / Config 데이터 전달| Node

    %% 스타일링
    style Core fill:#f96,stroke:#333
    style Infra fill:#3cf,stroke:#333
    style Boot fill:#9f9,stroke:#333
    style CP fill:#f9f,stroke:#333
```

```sh
# 프로바이더 확인
kubectl get providers.clusterctl.cluster.x-k8s.io -A
AGE   TYPE                     PROVIDER      VERSION
capd-system                         infrastructure-docker   91s   InfrastructureProvider   docker        v1.12.3
capi-kubeadm-bootstrap-system       bootstrap-kubeadm       92s   BootstrapProvider        kubeadm       v1.12.3
capi-kubeadm-control-plane-system   control-plane-kubeadm   92s   ControlPlaneProvider     kubeadm       v1.12.3
capi-system                         cluster-api             92s   CoreProvider             cluster-api   v1.12.3

# capi CoreProvider 컨트롤러
# cluster,  MachineDeployment, MachineSet, Machine CRD 관리
kubectl get providers -n capi-system cluster-api -o yaml
apiVersion: clusterctl.cluster.x-k8s.io/v1alpha3
kind: Provider
metadata:
  creationTimestamp: "2026-02-18T05:13:39Z"
  generation: 1
  labels:
    cluster.x-k8s.io/provider: cluster-api
    clusterctl.cluster.x-k8s.io: ""
    clusterctl.cluster.x-k8s.io/core: inventory
  name: cluster-api
  namespace: capi-system
  resourceVersion: "1405"
  uid: dd415ad6-1140-46b7-8464-2401db8b7d8f
providerName: cluster-api
type: CoreProvider
version: v1.12.3

# BootstrapProvider 노드를 k8s로 부팅하는 역할
# cloud-init user-data 생성 및 kubeadm join, init config 
kubectl get providers -n capi-kubeadm-bootstrap-system bootstrap-kubeadm -o yaml
apiVersion: clusterctl.cluster.x-k8s.io/v1alpha3
kind: Provider
metadata:
  creationTimestamp: "2026-02-18T05:13:39Z"
  generation: 1
  labels:
    cluster.x-k8s.io/provider: bootstrap-kubeadm
    clusterctl.cluster.x-k8s.io: ""
    clusterctl.cluster.x-k8s.io/core: inventory
  name: bootstrap-kubeadm
  namespace: capi-kubeadm-bootstrap-system
  resourceVersion: "1475"
  uid: 161792ae-4249-45e8-a353-aacd6f3ce024
providerName: kubeadm
type: BootstrapProvider
version: v1.12.3

# ControlPlaneProvider 컨트롤 플레인 전용 머신 관리
# kubeadmcontrolplane 리소스 관리, CP 노드 스케일링, etcd 포함 업그레이드 관리
kubectl get providers -n capi-kubeadm-control-plane-system control-plane-kubeadm -o yaml
apiVersion: clusterctl.cluster.x-k8s.io/v1alpha3
kind: Provider
metadata:
  creationTimestamp: "2026-02-18T05:13:39Z"
  generation: 1
  labels:
    cluster.x-k8s.io/provider: control-plane-kubeadm
    clusterctl.cluster.x-k8s.io: ""
    clusterctl.cluster.x-k8s.io/core: inventory
  name: control-plane-kubeadm
  namespace: capi-kubeadm-control-plane-system
  resourceVersion: "1534"
  uid: 894ed459-dd80-412c-b6f6-1620ed111da7
providerName: kubeadm
type: ControlPlaneProvider
version: v1.12.3

# InfrastructureProvider
# 실제 인프라 프로비저닝 담당, 현재는 docker이지만, 오픈스택, aws, gcp, 다양한 프로바이더를 사용할수 있다.
kubectl get providers -n capd-system infrastructure-docker -o yaml
apiVersion: clusterctl.cluster.x-k8s.io/v1alpha3
kind: Provider
metadata:
  creationTimestamp: "2026-02-18T05:13:40Z"
  generation: 1
  labels:
    cluster.x-k8s.io/provider: infrastructure-docker
    clusterctl.cluster.x-k8s.io: ""
    clusterctl.cluster.x-k8s.io/core: inventory
  name: infrastructure-docker
  namespace: capd-system
  resourceVersion: "1602"
  uid: c70d09d8-ce21-4d70-bc31-b9d3fcd6d78e
providerName: docker
type: InfrastructureProvider
version: v1.12.3

# cert-manager 확인
kubectl get crd | grep cert
certificaterequests.cert-manager.io                          2026-02-18T05:13:23Z
certificates.cert-manager.io                                 2026-02-18T05:13:23Z
challenges.acme.cert-manager.io                              2026-02-18T05:13:22Z
clusterissuers.cert-manager.io                               2026-02-18T05:13:23Z
issuers.cert-manager.io                                      2026-02-18T05:13:23Z
orders.acme.cert-manager.io                                  2026-02-18T05:13:22Z

# cer-manager 리소스 확인
kubectl get deploy,pod,svc,ep,cm,secret,sa -n cert-manager
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cert-manager              1/1     1            1           2m52s
deployment.apps/cert-manager-cainjector   1/1     1            1           2m52s
deployment.apps/cert-manager-webhook      1/1     1            1           2m52s
NAME                                           READY   STATUS    RESTARTS   AGE
pod/cert-manager-845844dd8-8vdx9               1/1     Running   0          2m52s
pod/cert-manager-cainjector-7b5d65fbcb-vc2nz   1/1     Running   0          2m52s
pod/cert-manager-webhook-6fcf4cb6c-772kf       1/1     Running   0          2m52s
NAME                              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)            AGE
service/cert-manager              ClusterIP   10.96.61.203   <none>        9402/TCP           2m52s
service/cert-manager-cainjector   ClusterIP   10.96.41.108   <none>        9402/TCP           2m52s
service/cert-manager-webhook      ClusterIP   10.96.6.187    <none>        443/TCP,9402/TCP   2m52s
NAME                                ENDPOINTS                          AGE
endpoints/cert-manager              10.244.0.8:9402                    2m52s
endpoints/cert-manager-cainjector   10.244.0.6:9402                    2m52s
endpoints/cert-manager-webhook      10.244.0.7:10250,10.244.0.7:9402   2m52s
NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      2m53s
NAME                             TYPE     DATA   AGE
secret/cert-manager-webhook-ca   Opaque   3      2m44s
NAME                                     AGE
serviceaccount/cert-manager              2m52s
serviceaccount/cert-manager-cainjector   2m52s
serviceaccount/cert-manager-webhook      2m52s
serviceaccount/default                   2m53s

# issuers 확인
kubectl get issuers.cert-manager.io -A                    
NAMESPACE                           NAME                                           READY   AGE
capd-system                         capd-selfsigned-issuer                         True    2m50s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-selfsigned-issuer       True    2m50s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-selfsigned-issuer   True    2m50s
capi-system                         capi-selfsigned-issuer                         True    2m51s

# certificaterequests 확인
kubectl get certificaterequests.cert-manager.io -A -owide 
NAMESPACE                           NAME                                        APPROVED   DENIED   READY   ISSUER                                         REQUESTER                                         STATUS                                         AGE
capd-system                         capd-serving-cert-1                         True                True    capd-selfsigned-issuer                         system:serviceaccount:cert-manager:cert-manager   Certificate fetched from issuer successfully   3m6s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-serving-cert-1       True                True    capi-kubeadm-bootstrap-selfsigned-issuer       system:serviceaccount:cert-manager:cert-manager   Certificate fetched from issuer successfully   3m7s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-serving-cert-1   True                True    capi-kubeadm-control-plane-selfsigned-issuer   system:serviceaccount:cert-manager:cert-manager   Certificate fetched from issuer successfully   3m7s
capi-system                         capi-serving-cert-1                         True                True    capi-selfsigned-issuer                         system:serviceaccount:cert-manager:cert-manager   Certificate fetched from issuer successfully   3m8s

# certificates 확인
kubectl get certificates.cert-manager.io -A -owide
NAMESPACE                           NAME                                      READY   SECRET                                            ISSUER                                         STATUS                                          AGE
capd-system                         capd-serving-cert                         True    capd-webhook-service-cert                         capd-selfsigned-issuer                         Certificate is up to date and has not expired   3m18s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-serving-cert       True    capi-kubeadm-bootstrap-webhook-service-cert       capi-kubeadm-bootstrap-selfsigned-issuer       Certificate is up to date and has not expired   3m18s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-serving-cert   True    capi-kubeadm-control-plane-webhook-service-cert   capi-kubeadm-control-plane-selfsigned-issuer   Certificate is up to date and has not expired   3m18s
capi-system                         capi-serving-cert                         True    capi-webhook-service-cert                         capi-selfsigned-issuer                         Certificate is up to date and has not expired   3m19
```


### 첫 번째 워크로드 클러스터 생성 [^2]
```sh
# 모니터링 
watch -d "docker ps ; echo ; clusterctl describe cluster capi-quickstart"

# 파드, 서비스, 클러스터명 정의, PSS 비활성화
export SERVICE_CIDR=["10.20.0.0/16"]
export POD_CIDR=["10.10.0.0/16"]
export SERVICE_DOMAIN="myk8s-1.local"
export POD_SECURITY_STANDARD_ENABLED="false"

# dry-run
# 템플릿 생성
clusterctl generate cluster capi-quickstart --flavor development \
  --kubernetes-version v1.34.3 \
  --control-plane-machine-count=3 \
  --worker-machine-count=3 \
  > capi-quickstart.yaml

open capi-quickstart.yaml

# 다양한 리소스 존재
cat capi-quickstart.yaml | grep -E '^apiVersion:|^kind:'
apiVersion: cluster.x-k8s.io/v1beta2
kind: ClusterClass
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: DockerClusterTemplate
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: KubeadmControlPlaneTemplate
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: DockerMachineTemplate
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: DockerMachineTemplate
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: DockerMachinePoolTemplate
apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
kind: KubeadmConfigTemplate
apiVersion: cluster.x-k8s.io/v1beta2
kind: Cluster

# 워크로드 클러스터 배포
kubectl apply -f capi-quickstart.yaml

# 워크로드 클러스터 상태 확인
kubectl get cluster -o wide
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP CURRENT   CP READY   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W CURRENT   W READY   W AVAILABLE   W UP-TO-DATE   PAUSED   PHASE         AGE   VERSION
capi-quickstart   quick-start    False       3            1            0          0              1               3           3           0         0             3              False    Provisioned   22s   v1.34.3

# 세부사항 확인
clusterctl describe cluster capi-quickstart
NAME                                                             REPLICAS AVAILABLE READY UP TO DATE STATUS REASON        SINCE MESSAGE                                                                                              
Cluster/capi-quickstart                                          4/6      0         0     4          False  NotAvailable  39s   * RemoteConnectionProbe: Remote connection not established yet                                       
│                                                                                                                              * ControlPlaneAvailable: Control plane not yet initialized                                           
│                                                                                                                              * WorkersAvailable:                                                                                  
│                                                                                                                                * MachineDeployment capi-quickstart-md-0-xtlgs: 0 available replicas, at least 3 required          
│                                                                                                                                  (spec.strategy.rollout.maxUnavailable is 0, spec.replicas is 3)                                  
├─ClusterInfrastructure - DockerCluster/capi-quickstart-47ph7                                      True   Ready         32s                                                                                                        
├─ControlPlane - KubeadmControlPlane/capi-quickstart-mstjv     1/3      0         0     1          False  NotAvailable  38s   Control plane not yet initialized                                                                    
│ └─Machine/capi-quickstart-mstjv-64npq                       1        0         0     1          False  NotReady      30s   * InfrastructureReady:                                                                               
│                                                                                                                                * BootstrapExecSucceeded: NotSucceeded                                                             
│                                                                                                                              * NodeHealthy: Waiting for Cluster control plane to be initialized                                   
│                                                                                                                              * Control plane components: Waiting for Cluster control plane to be initialized                      
│                                                                                                                              * EtcdMemberHealthy: Waiting for Cluster control plane to be initialized                             
└─Workers                      
  └─MachineDeployment/capi-quickstart-md-0-xtlgs               3/3      0         0     3          False  NotAvailable  38s   0 available replicas, at least 3 required (spec.strategy.rollout.maxUnavailable is 0, spec.replicas  
    │                                                                                                                          is 3)                                                                                                
    └─3 Machines...                                                     0         0     3          False  NotReady      23s   See capi-quickstart-md-0-xtlgs-6pmbd-jmfm7, capi-quickstart-md-0-xtlgs-6pmbd-jwqxd, ...              

# 컨테이너 확인
# 새로운 node 컨테이너가 존재한다.
docker ps
CONTAINER ID   IMAGE                                COMMAND                   CREATED              STATUS              PORTS                                                             NAMES
21938ce2dedf   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   About a minute ago   Up 59 seconds       127.0.0.1:55004->6443/tcp                                         capi-quickstart-mstjv-b6z5x
30c560fc529e   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   About a minute ago   Up About a minute   127.0.0.1:55003->6443/tcp                                         capi-quickstart-mstjv-twpml
90e69086f986   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   About a minute ago   Up About a minute                                                                     capi-quickstart-md-0-xtlgs-6pmbd-jmfm7
62678b4242bc   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   About a minute ago   Up About a minute                                                                     capi-quickstart-md-0-xtlgs-6pmbd-zlhrf
c8ca94ce8125   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   About a minute ago   Up About a minute                                                                     capi-quickstart-md-0-xtlgs-6pmbd-jwqxd
c9795cb90c3c   kindest/node:v1.34.3                 "/usr/local/bin/entr…"   2 minutes ago        Up 2 minutes        127.0.0.1:55002->6443/tcp                                         capi-quickstart-mstjv-64npq
26e142b6ea42   kindest/haproxy:v20230606-42a2262b   "haproxy -W -db -f /…"   2 minutes ago        Up 2 minutes        0.0.0.0:55000->6443/tcp, 0.0.0.0:55001->8404/tcp                  capi-quickstart-lb
9b88e3a6da34   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   16 minutes ago       Up 16 minutes       0.0.0.0:30000-30001->30000-30001/tcp, 127.0.0.1:56922->6443/tcp   myk8s-control-plane


# 로그를 확인하면 마치 vm이 실행되는 것과 동일한 cloud-init 로그가 출력된다.
docker logs -f capi-quickstart-mstjv-b6z5x
Welcome to Debian GNU/Linux 12 (bookworm)!
[  OK  ] Created slice kubelet.slic… used to run Kubernetes / Kubelet.
[  OK  ] Set up automount proc-sys-…rmats File System Automount Point.
         Mounting sys-kernel-debug.… - Kernel Debug File System...

# 워크로드 클러스터 kubeconfig 추출
clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig

# 노드 조회
kubectl --kubeconfig=capi-quickstart.kubeconfig get nodes -owide

# cni가 존재하지 않아 파드가 정상 기동 불가
# 칼리코 배포
kubectl --kubeconfig=capi-quickstart.kubeconfig apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 노드 조회
kubectl --kubeconfig=capi-quickstart.kubeconfig get nodes -owide
NAME                                     STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   Ready    <none>          6m18s   v1.34.3   172.19.0.6    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   Ready    <none>          6m17s   v1.34.3   172.19.0.5    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   Ready    <none>          61s     v1.34.3   172.19.0.7    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-6fz6t              Ready    control-plane   5m31s   v1.34.3   172.19.0.8    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-xdfcr              Ready    control-plane   43s     v1.34.3   172.19.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-xjjj8              Ready    control-plane   4m52s   v1.34.3   172.19.0.9    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0

# 워크로드 클러스터 정상 기동 확인
clusterctl describe cluster capi-quickstart
NAME                                                             REPLICAS AVAILABLE READY UP TO DATE STATUS REASON     SINCE  MESSAGE                                                                                  
Cluster/capi-quickstart                                          6/6      6         6     6          True   Available  58s                                                                                             
├─ClusterInfrastructure - DockerCluster/capi-quickstart-47ph7                                      True   Ready      12m                                                                                             
├─ControlPlane - KubeadmControlPlane/capi-quickstart-mstjv     3/3      3         3     3          True   Available  6m12s                                                                                           
│ └─3 Machines...                                                      3         3     3          True   Ready      97s    See capi-quickstart-mstjv-6fz6t, capi-quickstart-mstjv-xdfcr, ...                        
└─Workers
  └─MachineDeployment/capi-quickstart-md-0-xtlgs               3/3      3         3     3          True   Available  58s
    └─3 Machines...                                                     3         3     3          True   Ready      90s    See capi-quickstart-md-0-xtlgs-6pmbd-nr8qx, capi-quickstart-md-0-xtlgs-6pmbd-pnqhd, ...  
```


### 워크로드 클러스터 구조
- clusterclasses
  - cluster
    - KubeadmControlPlane
      - kubeadmconfigtemplate
    -  machinedeployments
       - machinesets
         - machines
         - machinehealthchecks
    - DockerCluster
      - dockerclustertemplate
      - dockermachinetemplate

```mermaid
%% graph TD
    %% 상위 정의 및 템플릿
    %%CC[ClusterClass] -->|Definitions| C[Cluster]
    
    %% Cluster 리소스 연결
%%    C -->|Control Plane Ref| KCP[KubeadmControlPlane]
%%    C -->|Infrastructure Ref| DC[DockerCluster]
    
    %% Control Plane 상세
%%    KCP -->|Uses| KCT[KubeadmConfigTemplate]
    
    %% Infrastructure 상세
%%    DC -->|Uses| DCT[DockerClusterTemplate]
%%    DC -->|Uses| DMT[DockerMachineTemplate]
    
    %% Worker Nodes (Machine 관리 계층)
%%    C -->|Manages| MD[MachineDeployment]
%%    MD -->|Owns| MS[MachineSet]
%%    MS -->|Creates| M[Machine]
    
    %% Health Check & Infrastructure 연결
%%    M -->|Uses| DMT
%%    M -->|Monitored by| MHC[MachineHealthCheck]
%%    MHC -->|Targets| M

    %% 스타일링
%%    style CC fill:#f9f,stroke:#333,stroke-width:2px
%%    style C fill:#bbf,stroke:#333,stroke-width:4px
%%    style MD fill:#dfd,stroke:#333
%%    style KCP fill:#ffd,stroke:#333
```

```sh
# clusterclasses 확인
# 클러스터 기본 템플릿 정보
kubectl get clusterclasses quick-start -o yaml

kubectl get clusterclasses -owide
NAME          PAUSED   VARIABLES READY   AGE
quick-start   False    True              39m

# 워크로드 클러스터 확인
kubectl get cluster -owide
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP CURRENT   CP READY   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W CURRENT   W READY   W AVAILABLE   W UP-TO-DATE   PAUSED   PHASE         AGE   VERSION
capi-quickstart   quick-start    True        3            3            3          3              3               3           3           3         3             3              False    Provisioned   39m   v1.34.3

# 클러스터 상세 정보 확인
# KubeadmControlPlane, DockerCluster, myk8s-1.local 도메인등
kubectl describe cluster capi-quickstart
Name:         capi-quickstart
Namespace:    default
Labels:       cluster.x-k8s.io/cluster-name=capi-quickstart
              topology.cluster.x-k8s.io/owned=
Annotations:  <none>
API Version:  cluster.x-k8s.io/v1beta2
Kind:         Cluster
Metadata:
  Creation Timestamp:  2026-02-18T05:18:48Z
  Finalizers:
    cluster.cluster.x-k8s.io
  Generation:        3
  Resource Version:  6798
  UID:               0d0a8329-098f-43e5-8f04-640778078a15
Spec:
  Cluster Network:
    Pods:
      Cidr Blocks:
        10.10.0.0/16
    Service Domain:  myk8s-1.local
    Services:
      Cidr Blocks:
        10.20.0.0/16
  Control Plane Endpoint:
    Host:  172.19.0.3
    Port:  6443
  Control Plane Ref:
    API Group:  controlplane.cluster.x-k8s.io
    Kind:       KubeadmControlPlane
    Name:       capi-quickstart-mstjv
  Infrastructure Ref:
    API Group:  infrastructure.cluster.x-k8s.io
    Kind:       DockerCluster
    Name:       capi-quickstart-47ph7
  Topology:
    Class Ref:
      Name:  quick-start
    Control Plane:
      Replicas:  3
    Variables:
      Name:   imageRepository
      Value:  
      Name:   etcdImageTag
      Value:  
      Name:   coreDNSImageTag
      Value:  
      Name:   podSecurityStandard
      Value:
        Audit:    restricted
        Enabled:  false
        Enforce:  baseline
        Warn:     restricted
    Version:      v1.34.3
    Workers:
      Machine Deployments:
        Class:     default-worker
        Name:      md-0
        Replicas:  3
Status:
  Conditions:
    Last Transition Time:  2026-02-18T05:30:45Z
    ...
  Control Plane:
    Available Replicas:   3
    Desired Replicas:     3
    Ready Replicas:       3
    Replicas:             3
    Up To Date Replicas:  3
  Deprecated:
    v1beta1:
      Conditions:
      ...
  Initialization:
    Control Plane Initialized:   true
    Infrastructure Provisioned:  true
  Observed Generation:           3
  Phase:                         Provisioned
  Workers:
    Available Replicas:   3
    Desired Replicas:     3
    Ready Replicas:       3
    Replicas:             3
    Up To Date Replicas:  3


# 워크로드 클러스터 etcd 이미지 태그 확인
kubectl --kubeconfig=capi-quickstart.kubeconfig get pod -n kube-system -l component=etcd -o yaml | grep image: | uniq
      image: registry.k8s.io/etcd:3.6.5-0

# kubeadmcontrolplane 정보 확인
kubectl get kubeadmcontrolplane -owide
NAME                    CLUSTER           AVAILABLE   DESIRED   CURRENT   READY   AVAILABLE   UP-TO-DATE   PAUSED   INITIALIZED   AGE   VERSION
capi-quickstart-mstjv   capi-quickstart   True        3         3         3       3           3            False    true          40m   v1.34.3

# ownerReferences.Kind: cluster
kubectl get kubeadmcontrolplane -o yaml
apiVersion: v1
items:
- apiVersion: controlplane.cluster.x-k8s.io/v1beta2
  kind: KubeadmControlPlane
  metadata:
    annotations:
      cluster.x-k8s.io/cloned-from-groupkind: KubeadmControlPlaneTemplate.controlplane.cluster.x-k8s.io
      cluster.x-k8s.io/cloned-from-name: quick-start-control-plane
    creationTimestamp: "2026-02-18T05:18:48Z"
    finalizers:
    - kubeadm.controlplane.cluster.x-k8s.io
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-mstjv
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "6795"
    uid: 1d73ac23-ca26-4925-9047-ca936b1686bc
  spec:
    kubeadmConfigSpec:
      clusterConfiguration:
        apiServer:
          certSANs:
          - localhost
          - 127.0.0.1
          - 0.0.0.0
          - host.docker.internal
      initConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
          - name: eviction-hard
            value: nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
          - name: eviction-hard
            value: nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%
    machineTemplate:
      metadata:
        labels:
          cluster.x-k8s.io/cluster-name: capi-quickstart
          topology.cluster.x-k8s.io/owned: ""
      spec:
        infrastructureRef:
          apiGroup: infrastructure.cluster.x-k8s.io
          kind: DockerMachineTemplate
          name: capi-quickstart-8mm46
    replicas: 3
    rollout:
      strategy:
        rollingUpdate:
          maxSurge: 1
        type: RollingUpdate
    version: v1.34.3
  status:
    availableReplicas: 3
    conditions:
    - lastTransitionTime: "2026-02-18T05:25:31Z"
    ...
    deprecated:
      v1beta1:
        conditions:
        ...
        readyReplicas: 3
        unavailableReplicas: 0
        updatedReplicas: 3
    initialization:
      controlPlaneInitialized: true
    lastRemediation:
      machine: capi-quickstart-mstjv-8w2bs
      retryCount: 1
      time: "2026-02-18T05:30:08Z"
    observedGeneration: 1
    readyReplicas: 3
    replicas: 3
    selector: cluster.x-k8s.io/cluster-name=capi-quickstart,cluster.x-k8s.io/control-plane
    upToDateReplicas: 3
    version: v1.34.3
kind: List
metadata:
  resourceVersion: ""


# kubeadmconfigtemplate 확인
# capi-* 실제 cluster 생성 시 만들어지는 복사본
# bootstraptemplate은 clusterclass에 속하는 설계용 템플릿
kubectl get kubeadmconfigtemplate
NAME                                           CLUSTERCLASS   CLUSTER           AGE
capi-quickstart-md-0-4btzq                                    capi-quickstart   41m
quick-start-default-worker-bootstraptemplate   quick-start                      41m


kubectl get kubeadmconfigtemplate -l cluster.x-k8s.io/cluster-name=capi-quickstart     
NAME                         CLUSTERCLASS   CLUSTER           AGE
capi-quickstart-md-0-4btzq                  capi-quickstart   41m

# 두 설정이 동일하다. 
kubectl get kubeadmconfigtemplate -l cluster.x-k8s.io/cluster-name=capi-quickstart -o yaml 
- apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
  kind: KubeadmConfigTemplate
  spec:
    template:
      spec:
        joinConfiguration:
          nodeRegistration:
            kubeletExtraArgs:
            - name: eviction-hard
              value: nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%
...
kubectl get kubeadmconfigtemplate quick-start-default-worker-bootstraptemplate -o yaml 
apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
kind: KubeadmConfigTemplate
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
          - name: eviction-hard
            value: nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%


# dockerclustertemplate 확인
kubectl get dockerclustertemplate
quick-start-cluster   42m

# 컨트롤 플레인의 port와 lb에 대한 설정 확인
kubectl describe dockerclustertemplate
API Version:  infrastructure.cluster.x-k8s.io/v1beta2
Kind:         DockerClusterTemplate
Spec:
  Template:
    Spec:
      Control Plane Endpoint:
        Port:  6443
      Load Balancer:

# 템플릿과 실제 리소스 두 개가 존재하는 이유. 사용자는 클러스터 생성 시 clusterclass를 사용하여 변수를 주입한 고유한 리소스를 생성하기 위함
kubectl get dockermachinetemplate
# 템플릿을 기반으로 만들어진 복제본(객체 인스턴스)
NAME                                         AGE
capi-quickstart-8mm46                        43m
capi-quickstart-md-0-txwbq                   43m
# clusterclass 원본 템플릿(객체)
quick-start-control-plane                    43m
quick-start-default-worker-machinetemplate   43m

# 도커 인프라 프로바이더에 의해 배포된 노드 템플릿
kubectl describe dockermachinetemplate quick-start-control-plane
Name:         quick-start-control-plane
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  infrastructure.cluster.x-k8s.io/v1beta2
Kind:         DockerMachineTemplate
Metadata:
  Creation Timestamp:  2026-02-18T05:18:48Z
  Generation:          1
  Owner References:
    API Version:     cluster.x-k8s.io/v1beta2
    Kind:            ClusterClass
    Name:            quick-start
    UID:             2c2f8165-3561-4deb-ae12-33da7a8f2e8a
  Resource Version:  2694
  UID:               7f4b5bad-f1d3-4c9b-9d03-d8b2a8a9d252
Spec:
  Template:
    Spec:
      Extra Mounts:
        Container Path:  /var/run/docker.sock
        Host Path:       /var/run/docker.sock
Status:
  Capacity:
    Cpu:     8
    Memory:  8630612Ki
Events:      <none

# 도커 인프라 프로바이더에 의해 배포된 컨트롤플레인 템플릿
kubectl describe dockermachinetemplate quick-start-default-worker-machinetemplate
Name:         quick-start-default-worker-machinetemplate
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  infrastructure.cluster.x-k8s.io/v1beta2
Kind:         DockerMachineTemplate
Metadata:
  Creation Timestamp:  2026-02-18T05:18:48Z
  Generation:          1
  Owner References:
    API Version:     cluster.x-k8s.io/v1beta2
    Kind:            ClusterClass
    Name:            quick-start
    UID:             2c2f8165-3561-4deb-ae12-33da7a8f2e8a
  Resource Version:  2696
  UID:               f7578d8d-54bb-4915-9510-6fd01bf12ab6
Spec:
  Template:
    Spec:
      Extra Mounts:
        Container Path:  /var/run/docker.sock
        Host Path:       /var/run/docker.sock
Status:
  Capacity:
    Cpu:     8
    Memory:  8630612Ki
Events:      <none>


kubectl get dockermachinetemplate -l cluster.x-k8s.io/cluster-name=capi-quickstart
NAME                         AGE
capi-quickstart-8mm46        44m
capi-quickstart-md-0-txwbq   44m

kubectl describe cluster capi-quickstart | grep DockerMachineTemplate
  Normal  TopologyCreate           44m                topology/cluster-controller  Created DockerMachineTemplate "default/capi-quickstart-8mm46"
  Normal  TopologyCreate           44m                topology/cluster-controller  Created DockerMachineTemplate "default/capi-quickstart-md-0-txwbq"


kubectl get dockermachinetemplate -l cluster.x-k8s.io/cluster-name=capi-quickstart -o yaml
apiVersion: v1
items:
- apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
  kind: DockerMachineTemplate
  metadata:
    annotations:
      cluster.x-k8s.io/cloned-from-groupkind: DockerMachineTemplate.infrastructure.cluster.x-k8s.io
      cluster.x-k8s.io/cloned-from-name: quick-start-control-plane
    creationTimestamp: "2026-02-18T05:18:48Z"
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-8mm46
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "2719"
    uid: 517e8c94-fe82-4e1c-8bf4-ab8c9ab7c46c
  spec:
    template:
      spec:
        customImage: kindest/node:v1.34.3
        extraMounts:
        - containerPath: /var/run/docker.sock
          hostPath: /var/run/docker.sock
  status:
    capacity:
      cpu: "8"
      memory: 8630612Ki
- apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
  kind: DockerMachineTemplate
  metadata:
    annotations:
      cluster.x-k8s.io/cloned-from-groupkind: DockerMachineTemplate.infrastructure.cluster.x-k8s.io
      cluster.x-k8s.io/cloned-from-name: quick-start-default-worker-machinetemplate
    creationTimestamp: "2026-02-18T05:18:49Z"
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/deployment-name: md-0
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-md-0-txwbq
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "2730"
    uid: 1e132d70-bc9c-4074-8eb3-fa49bc2daf9e
  spec:
    template:
      spec:
        customImage: kindest/node:v1.34.3
        extraMounts:
        - containerPath: /var/run/docker.sock
          hostPath: /var/run/docker.sock
  status:
    capacity:
      cpu: "8"
      memory: 8630612Ki
kind: List
metadata:
  resourceVersion: ""

# 컨트롤 플레인에 대한 설정은 KubeadmControlPlane이 처리한다.
k get machinedeployments
NAME                         CLUSTER           AVAILABLE   DESIRED   CURRENT   READY   AVAILABLE   UP-TO-DATE   PHASE     AGE   VERSION
capi-quickstart-md-0-xtlgs   capi-quickstart   True        3         3         3       3           3            Running   45m   v1.34.3

# machinedeployments 확인
k get machinedeployments -o yaml
apiVersion: v1
items:
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: MachineDeployment
  metadata:
    annotations:
      machinedeployment.clusters.x-k8s.io/revision: "1"
    creationTimestamp: "2026-02-18T05:18:49Z"
    finalizers:
    - machinedeployment.topology.cluster.x-k8s.io
    - cluster.x-k8s.io/machinedeployment
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/deployment-name: md-0
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-md-0-xtlgs
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "6602"
    uid: 336d39a1-99bd-469a-a37f-4aecdf4321e5
  spec:
    clusterName: capi-quickstart
    replicas: 3
    rollout:
      strategy:
        rollingUpdate:
          maxSurge: 1
          maxUnavailable: 0
        type: RollingUpdate
    selector:
      matchLabels:
        cluster.x-k8s.io/cluster-name: capi-quickstart
        topology.cluster.x-k8s.io/deployment-name: md-0
        topology.cluster.x-k8s.io/owned: ""
    template:
      metadata:
        labels:
          cluster.x-k8s.io/cluster-name: capi-quickstart
          topology.cluster.x-k8s.io/deployment-name: md-0
          topology.cluster.x-k8s.io/owned: ""
      spec:
        bootstrap:
          configRef:
            apiGroup: bootstrap.cluster.x-k8s.io
            kind: KubeadmConfigTemplate
            name: capi-quickstart-md-0-4btzq
        clusterName: capi-quickstart
        infrastructureRef:
          apiGroup: infrastructure.cluster.x-k8s.io
          kind: DockerMachineTemplate
          name: capi-quickstart-md-0-txwbq
        version: v1.34.3
  status:
    availableReplicas: 3
    conditions:
    - lastTransitionTime: "2026-02-18T05:30:45Z"
      ...
    deprecated:
      v1beta1:
        availableReplicas: 3
        conditions:
        ...
        readyReplicas: 3
        unavailableReplicas: 0
        updatedReplicas: 3
    observedGeneration: 1
    phase: Running
    readyReplicas: 3
    replicas: 3
    selector: cluster.x-k8s.io/cluster-name=capi-quickstart,topology.cluster.x-k8s.io/deployment-name=md-0,topology.cluster.x-k8s.io/owned=
    upToDateReplicas: 3
kind: List
metadata:
  resourceVersion: ""

# machinesets 확인
k get machinesets
NAME                               CLUSTER           DESIRED   CURRENT   READY   AVAILABLE   UP-TO-DATE   AGE   VERSION
capi-quickstart-md-0-xtlgs-6pmbd   capi-quickstart   3         3         3       3           3            46m   v1.34.3

k get machinesets -o yaml
apiVersion: v1
items:
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: MachineSet
  metadata:
    annotations:
      cluster.x-k8s.io/disable-machine-create: "false"
      machinedeployment.clusters.x-k8s.io/desired-replicas: "3"
      machinedeployment.clusters.x-k8s.io/max-replicas: "4"
      machinedeployment.clusters.x-k8s.io/revision: "1"
    creationTimestamp: "2026-02-18T05:18:49Z"
    finalizers:
    - cluster.x-k8s.io/machineset
    - machineset.topology.cluster.x-k8s.io
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      cluster.x-k8s.io/deployment-name: capi-quickstart-md-0-xtlgs
      machine-template-hash: 4251419600-6pmbd
      topology.cluster.x-k8s.io/deployment-name: md-0
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-md-0-xtlgs-6pmbd
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: MachineDeployment
      name: capi-quickstart-md-0-xtlgs
      uid: 336d39a1-99bd-469a-a37f-4aecdf4321e5
    resourceVersion: "6597"
    uid: 1c8c60c4-f8cc-4694-bfb1-e0f16c6f79af
  spec:
    clusterName: capi-quickstart
    replicas: 3
    selector:
      matchLabels:
        cluster.x-k8s.io/cluster-name: capi-quickstart
        machine-template-hash: 4251419600-6pmbd
        topology.cluster.x-k8s.io/deployment-name: md-0
        topology.cluster.x-k8s.io/owned: ""
    template:
      metadata:
        labels:
          cluster.x-k8s.io/cluster-name: capi-quickstart
          machine-template-hash: 4251419600-6pmbd
          topology.cluster.x-k8s.io/deployment-name: md-0
          topology.cluster.x-k8s.io/owned: ""
      spec:
        bootstrap:
          configRef:
            apiGroup: bootstrap.cluster.x-k8s.io
            kind: KubeadmConfigTemplate
            name: capi-quickstart-md-0-4btzq
        clusterName: capi-quickstart
        infrastructureRef:
          apiGroup: infrastructure.cluster.x-k8s.io
          kind: DockerMachineTemplate
          name: capi-quickstart-md-0-txwbq
        version: v1.34.3
  status:
    availableReplicas: 3
    conditions:
    - lastTransitionTime: "2026-02-18T05:30:21Z"
      ...
    deprecated:
      v1beta1:
        availableReplicas: 3
        conditions:
        - lastTransitionTime: "2026-02-18T05:30:45Z"
          status: "True"
          ...
        fullyLabeledReplicas: 3
        readyReplicas: 3
    observedGeneration: 1
    readyReplicas: 3
    replicas: 3
    selector: cluster.x-k8s.io/cluster-name=capi-quickstart,machine-template-hash=4251419600-6pmbd,topology.cluster.x-k8s.io/deployment-name=md-0,topology.cluster.x-k8s.io/owned=
    upToDateReplicas: 3
kind: List
metadata:
  resourceVersion: ""

# 개별 머신에 대한 정보 확인
k get machines  -o wide
NAME                                     CLUSTER           NODE NAME                                PROVIDER ID                                         READY   AVAILABLE   UP-TO-DATE   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         PAUSED   PHASE     AGE   VERSION
capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   capi-quickstart   capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   docker:////capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   True    True        True         172.19.0.6    172.19.0.6    Debian GNU/Linux 12 (bookworm)   False    Running   40m   v1.34.3
capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   capi-quickstart   capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   docker:////capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   True    True        True         172.19.0.5    172.19.0.5    Debian GNU/Linux 12 (bookworm)   False    Running   40m   v1.34.3
capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   capi-quickstart   capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   docker:////capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   True    True        True         172.19.0.7    172.19.0.7    Debian GNU/Linux 12 (bookworm)   False    Running   35m   v1.34.3
capi-quickstart-mstjv-6fz6t              capi-quickstart   capi-quickstart-mstjv-6fz6t              docker:////capi-quickstart-mstjv-6fz6t              True    True        True         172.19.0.8    172.19.0.8    Debian GNU/Linux 12 (bookworm)   False    Running   39m   v1.34.3
capi-quickstart-mstjv-xdfcr              capi-quickstart   capi-quickstart-mstjv-xdfcr              docker:////capi-quickstart-mstjv-xdfcr              True    True        True         172.19.0.4    172.19.0.4    Debian GNU/Linux 12 (bookworm)   False    Running   35m   v1.34.3
capi-quickstart-mstjv-xjjj8              capi-quickstart   capi-quickstart-mstjv-xjjj8              docker:////capi-quickstart-mstjv-xjjj8              True    True        True         172.19.0.9    172.19.0.9    Debian GNU/Linux 12 (bookworm)   False    Running   39m   v1.34.3


# 컨트롤 플레인 머신 정보 확인
k get machines -l cluster.x-k8s.io/control-plane -o yaml
apiVersion: v1
items:
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: Machine
  metadata:
    annotations:
      controlplane.cluster.x-k8s.io/remediation-for: '{"machine":"capi-quickstart-mstjv-twpml","timestamp":"2026-02-18T05:25:29Z","retryCount":0}'
      pre-terminate.delete.hook.machine.cluster.x-k8s.io/kcp-cleanup: ""
    creationTimestamp: "2026-02-18T05:25:31Z"
    finalizers:
    - machine.cluster.x-k8s.io
    generation: 3
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      cluster.x-k8s.io/control-plane: ""
      cluster.x-k8s.io/control-plane-name: capi-quickstart-mstjv
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-mstjv-6fz6t
    namespace: default
    ownerReferences:
    - apiVersion: controlplane.cluster.x-k8s.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: KubeadmControlPlane
      name: capi-quickstart-mstjv
      uid: 1d73ac23-ca26-4925-9047-ca936b1686bc
    resourceVersion: "6567"
    uid: 13c5fff0-9ee8-4b78-b864-ec77edd6eb8c
  spec:
    bootstrap:
      configRef:
        apiGroup: bootstrap.cluster.x-k8s.io
        kind: KubeadmConfig
        name: capi-quickstart-mstjv-6fz6t
      dataSecretName: capi-quickstart-mstjv-6fz6t
    clusterName: capi-quickstart
    deletion:
      nodeDeletionTimeoutSeconds: 10
    infrastructureRef:
      apiGroup: infrastructure.cluster.x-k8s.io
      kind: DockerMachine
      name: capi-quickstart-mstjv-6fz6t
    providerID: docker:////capi-quickstart-mstjv-6fz6t
    readinessGates:
    - conditionType: APIServerPodHealthy
    - conditionType: ControllerManagerPodHealthy
    - conditionType: SchedulerPodHealthy
    - conditionType: EtcdPodHealthy
    - conditionType: EtcdMemberHealthy
    version: v1.34.3
  status:
    addresses:
    - address: capi-quickstart-mstjv-6fz6t
      type: Hostname
    - address: 172.19.0.8
      type: InternalIP
    - address: 172.19.0.8
      type: ExternalIP
    certificatesExpiryDate: "2027-02-18T05:25:41Z"
    conditions:
    - lastTransitionTime: "2026-02-18T05:30:18Z"
       ...
    deprecated:
      v1beta1:
        conditions:
        - lastTransitionTime: "2026-02-18T05:25:31Z"
          status: "True"
          type: Ready
            ...
    initialization:
      bootstrapDataSecretCreated: true
      infrastructureProvisioned: true
    lastUpdated: "2026-02-18T05:26:04Z"
    nodeInfo:
      architecture: arm64
      bootID: b71f28ab-a139-4eb5-89d1-17a8b507206d
      containerRuntimeVersion: containerd://2.2.0
      kernelVersion: 6.10.14-linuxkit
      kubeProxyVersion: ""
      kubeletVersion: v1.34.3
      machineID: 4e1ac8ad6a4247ac8c58b8f07be02611
      operatingSystem: linux
      osImage: Debian GNU/Linux 12 (bookworm)
      swap:
        capacity: 1073737728
      systemUUID: 4e1ac8ad6a4247ac8c58b8f07be02611
    nodeRef:
      name: capi-quickstart-mstjv-6fz6t
    observedGeneration: 3
    phase: Running
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: Machine
  metadata:
    annotations:
      controlplane.cluster.x-k8s.io/remediation-for: '{"machine":"capi-quickstart-mstjv-8w2bs","timestamp":"2026-02-18T05:30:08Z","retryCount":1}'
      pre-terminate.delete.hook.machine.cluster.x-k8s.io/kcp-cleanup: ""
    creationTimestamp: "2026-02-18T05:30:13Z"
    finalizers:
    - machine.cluster.x-k8s.io
    generation: 3
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      cluster.x-k8s.io/control-plane: ""
      cluster.x-k8s.io/control-plane-name: capi-quickstart-mstjv
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-mstjv-xdfcr
    namespace: default
    ownerReferences:
    - apiVersion: controlplane.cluster.x-k8s.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: KubeadmControlPlane
      name: capi-quickstart-mstjv
      uid: 1d73ac23-ca26-4925-9047-ca936b1686bc
    resourceVersion: "6856"
    uid: 0f457333-5bc9-4dbf-b8c5-5a2f5cf126f1
  spec:
    bootstrap:
      configRef:
        apiGroup: bootstrap.cluster.x-k8s.io
        kind: KubeadmConfig
        name: capi-quickstart-mstjv-xdfcr
      dataSecretName: capi-quickstart-mstjv-xdfcr
    clusterName: capi-quickstart
    deletion:
      nodeDeletionTimeoutSeconds: 10
    infrastructureRef:
      apiGroup: infrastructure.cluster.x-k8s.io
      kind: DockerMachine
      name: capi-quickstart-mstjv-xdfcr
    providerID: docker:////capi-quickstart-mstjv-xdfcr
    readinessGates:
    - conditionType: APIServerPodHealthy
    - conditionType: ControllerManagerPodHealthy
    - conditionType: SchedulerPodHealthy
    - conditionType: EtcdPodHealthy
    - conditionType: EtcdMemberHealthy
    version: v1.34.3
  status:
    addresses:
    - address: capi-quickstart-mstjv-xdfcr
      type: Hostname
    - address: 172.19.0.4
      type: InternalIP
    - address: 172.19.0.4
      type: ExternalIP
    certificatesExpiryDate: "2027-02-18T05:30:28Z"
    conditions:
    - lastTransitionTime: "2026-02-18T05:31:34Z"
      ...
    deprecated:
      v1beta1:
        conditions:
        - lastTransitionTime: "2026-02-18T05:30:13Z"
          status: "True"
          type: Ready
          ...
    initialization:
      bootstrapDataSecretCreated: true
      infrastructureProvisioned: true
    lastUpdated: "2026-02-18T05:30:52Z"
    nodeInfo:
      architecture: arm64
      bootID: b71f28ab-a139-4eb5-89d1-17a8b507206d
      containerRuntimeVersion: containerd://2.2.0
      kernelVersion: 6.10.14-linuxkit
      kubeProxyVersion: ""
      kubeletVersion: v1.34.3
      machineID: a75b84b2457146d5a5dee8f50114e03d
      operatingSystem: linux
      osImage: Debian GNU/Linux 12 (bookworm)
      swap:
        capacity: 1073737728
      systemUUID: a75b84b2457146d5a5dee8f50114e03d
    nodeRef:
      name: capi-quickstart-mstjv-xdfcr
    observedGeneration: 3
    phase: Running
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: Machine
  metadata:
    annotations:
      controlplane.cluster.x-k8s.io/remediation-for: '{"machine":"capi-quickstart-mstjv-b6z5x","timestamp":"2026-02-18T05:26:20Z","retryCount":0}'
      pre-terminate.delete.hook.machine.cluster.x-k8s.io/kcp-cleanup: ""
    creationTimestamp: "2026-02-18T05:26:22Z"
    finalizers:
    - machine.cluster.x-k8s.io
    generation: 3
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      cluster.x-k8s.io/control-plane: ""
      cluster.x-k8s.io/control-plane-name: capi-quickstart-mstjv
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-mstjv-xjjj8
    namespace: default
    ownerReferences:
    - apiVersion: controlplane.cluster.x-k8s.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: KubeadmControlPlane
      name: capi-quickstart-mstjv
      uid: 1d73ac23-ca26-4925-9047-ca936b1686bc
    resourceVersion: "6560"
    uid: 515d5dec-039e-4284-989c-8ac74414870d
  spec:
    bootstrap:
      configRef:
        apiGroup: bootstrap.cluster.x-k8s.io
        kind: KubeadmConfig
        name: capi-quickstart-mstjv-xjjj8
      dataSecretName: capi-quickstart-mstjv-xjjj8
    clusterName: capi-quickstart
    deletion:
      nodeDeletionTimeoutSeconds: 10
    infrastructureRef:
      apiGroup: infrastructure.cluster.x-k8s.io
      kind: DockerMachine
      name: capi-quickstart-mstjv-xjjj8
    providerID: docker:////capi-quickstart-mstjv-xjjj8
    readinessGates:
    - conditionType: APIServerPodHealthy
    - conditionType: ControllerManagerPodHealthy
    - conditionType: SchedulerPodHealthy
    - conditionType: EtcdPodHealthy
    - conditionType: EtcdMemberHealthy
    version: v1.34.3
  status:
    addresses:
    - address: capi-quickstart-mstjv-xjjj8
      type: Hostname
    - address: 172.19.0.9
      type: InternalIP
    - address: 172.19.0.9
      type: ExternalIP
    certificatesExpiryDate: "2027-02-18T05:26:31Z"
    conditions:
    - lastTransitionTime: "2026-02-18T05:30:06Z"
      message: ""
      observedGeneration: 3
      reason: Available
      status: "True"
      type: Available
      ...  
    deprecated:
      v1beta1:
        conditions:
        - lastTransitionTime: "2026-02-18T05:26:22Z"
          status: "True"
          type: Ready
          ... 
    initialization:
      bootstrapDataSecretCreated: true
      infrastructureProvisioned: true
    lastUpdated: "2026-02-18T05:26:43Z"
    nodeInfo:
      architecture: arm64
      bootID: b71f28ab-a139-4eb5-89d1-17a8b507206d
      containerRuntimeVersion: containerd://2.2.0
      kernelVersion: 6.10.14-linuxkit
      kubeProxyVersion: ""
      kubeletVersion: v1.34.3
      machineID: 55443a9509cf43eca79be921105d9f40
      operatingSystem: linux
      osImage: Debian GNU/Linux 12 (bookworm)
      swap:
        capacity: 1073737728
      systemUUID: 55443a9509cf43eca79be921105d9f40
    nodeRef:
      name: capi-quickstart-mstjv-xjjj8
    observedGeneration: 3
    phase: Running
kind: List
metadata:
  resourceVersion: ""

# 머신 헬스체크 상태
k get machinehealthchecks -owide
NAME                         CLUSTER           REPLICAS   HEALTHY   PAUSED   AGE
capi-quickstart-md-0-xtlgs   capi-quickstart   3          3         False    47m
capi-quickstart-mstjv        capi-quickstart   3          3         False    47m


k get machinehealthchecks -o yaml
apiVersion: v1
items:
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: MachineHealthCheck
  metadata:
    creationTimestamp: "2026-02-18T05:18:49Z"
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-md-0-xtlgs
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "6595"
    uid: dc9b1afd-3031-42ea-af29-c33f6a714457
  spec:
    checks:
      nodeStartupTimeoutSeconds: 600
      unhealthyMachineConditions:
      - status: Unknown
        timeoutSeconds: 300
        type: NodeReady
      - status: "False"
        timeoutSeconds: 300
        type: NodeReady
      unhealthyNodeConditions:
      - status: Unknown
        timeoutSeconds: 300
        type: Ready
      - status: "False"
        timeoutSeconds: 300
        type: Ready
    clusterName: capi-quickstart
    selector:
      matchLabels:
        topology.cluster.x-k8s.io/deployment-name: md-0
        topology.cluster.x-k8s.io/owned: ""
  status:
    conditions:
    - lastTransitionTime: "2026-02-18T05:18:49Z"
      message: ""
      observedGeneration: 1
      reason: RemediationAllowed
      status: "True"
      type: RemediationAllowed
    - lastTransitionTime: "2026-02-18T05:18:49Z"
      message: ""
      observedGeneration: 1
      reason: NotPaused
      status: "False"
      type: Paused
    currentHealthy: 3
    deprecated:
      v1beta1:
        conditions:
        - lastTransitionTime: "2026-02-18T05:18:49Z"
          status: "True"
          type: RemediationAllowed
    expectedMachines: 3
    observedGeneration: 1
    remediationsAllowed: 3
    targets:
    - capi-quickstart-md-0-xtlgs-6pmbd-nr8qx
    - capi-quickstart-md-0-xtlgs-6pmbd-pnqhd
    - capi-quickstart-md-0-xtlgs-6pmbd-qr5kr
- apiVersion: cluster.x-k8s.io/v1beta2
  kind: MachineHealthCheck
  metadata:
    creationTimestamp: "2026-02-18T05:18:48Z"
    generation: 1
    labels:
      cluster.x-k8s.io/cluster-name: capi-quickstart
      topology.cluster.x-k8s.io/owned: ""
    name: capi-quickstart-mstjv
    namespace: default
    ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta2
      kind: Cluster
      name: capi-quickstart
      uid: 0d0a8329-098f-43e5-8f04-640778078a15
    resourceVersion: "6793"
    uid: 32cf956a-350d-475b-b590-1cdb2197b853
  spec:
    checks:
      nodeStartupTimeoutSeconds: 600
      unhealthyMachineConditions:
      - status: Unknown
        timeoutSeconds: 300
        type: NodeReady
      - status: "False"
        timeoutSeconds: 300
        type: NodeReady
      unhealthyNodeConditions:
      - status: Unknown
        timeoutSeconds: 300
        type: Ready
      - status: "False"
        timeoutSeconds: 300
        type: Ready
    clusterName: capi-quickstart
    selector:
      matchLabels:
        cluster.x-k8s.io/control-plane: ""
        topology.cluster.x-k8s.io/owned: ""
  status:
    conditions:
    - lastTransitionTime: "2026-02-18T05:18:48Z"
      message: ""
      observedGeneration: 1
      reason: RemediationAllowed
      status: "True"
      type: RemediationAllowed
    - lastTransitionTime: "2026-02-18T05:18:48Z"
      message: ""
      observedGeneration: 1
      reason: NotPaused
      status: "False"
      type: Paused
    currentHealthy: 3
    deprecated:
      v1beta1:
        conditions:
        - lastTransitionTime: "2026-02-18T05:18:48Z"
          status: "True"
          type: RemediationAllowed
    expectedMachines: 3
    observedGeneration: 1
    remediationsAllowed: 3
    targets:
    - capi-quickstart-mstjv-6fz6t
    - capi-quickstart-mstjv-xdfcr
    - capi-quickstart-mstjv-xjjj8
kind: List
metadata:
  resourceVersion: ""
```


### 워크로드 클러스터 애플리케이션 배포
```sh
# 단축키 지정
alias k8s1='kubectl --kubeconfig=capi-quickstart.kubeconfig'

# 클러스터 정보
k8s1 cluster-info
Kubernetes control plane is running at https://localhost:55000

# kube ops view 배포
helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 \
  --set env.TZ="Asia/Seoul" --namespace kube-system --kubeconfig=capi-quickstart.kubeconfig

# 
helm list --kubeconfig=capi-quickstart.kubeconfig -n kube-system
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                      APP VERSION
kube-ops-view   kube-system     1               2026-02-18 15:29:50.77349 +0900 KST     deployed        kube-ops-view-1.2.2        20.4.0     

#
k8s1 get svc,ep -n kube-system kube-ops-view
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/kube-ops-view   ClusterIP   10.20.151.95   <none>        8080/TCP   24s
NAME                      ENDPOINTS         AGE
endpoints/kube-ops-view   10.10.24.1:8080   23s

# 포트포워딩
k8s1 -n kube-system port-forward svc/kube-ops-view 8080:8080 &
open "http://127.0.0.1:8080/#scale=1.5"

docker ps

# 샘플 앱 배포
cat << EOF | kubectl --kubeconfig=capi-quickstart.kubeconfig apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webpod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webpod
  template:
    metadata:
      labels:
        app: webpod
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - sample-app
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: webpod
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: webpod
  labels:
    app: webpod
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30003
  type: NodePort
EOF

# 파드 확인
k8s1 get deploy,pod,svc,ep -owide
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES           SELECTOR
deployment.apps/webpod   3/3     3            3           14s   webpod       traefik/whoami   app=webpod
NAME                          READY   STATUS    RESTARTS   AGE   IP             NODE                                     NOMINATED NODE   READINESS GATES
pod/webpod-59589fb744-jnh4r   1/1     Running   0          14s   10.10.175.1    capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   <none>           <none>
pod/webpod-59589fb744-phkz5   1/1     Running   0          14s   10.10.24.2     capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   <none>           <none>
pod/webpod-59589fb744-qvjxn   1/1     Running   0          14s   10.10.33.193   capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   <none>           <none>
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE   SELECTOR
service/kubernetes   ClusterIP   10.20.0.1       <none>        443/TCP        71m   <none>
service/webpod       NodePort    10.20.104.115   <none>        80:30003/TCP   14s   app=webpod
NAME                   ENDPOINTS                                         AGE
endpoints/kubernetes   172.19.0.4:6443,172.19.0.8:6443,172.19.0.9:6443   71m
endpoints/webpod       10.10.175.1:80,10.10.24.2:80,10.10.33.193:80      14s

# 컨트롤 플레인 컨테이너 추출
docker ps
CT1=capi-quickstart-mstjv-xdfcr

# curl 테스트
docker exec -it myk8s-control-plane curl -s $CT1:30003
while true; do docker exec -it myk8s-control-plane curl -s $CT1:30003 | grep Hostname; date; sleep 1; done

# haproxy 확인
docker ps
26e142b6ea42   kindest/haproxy:v20230606-42a2262b   "haproxy -W -db -f /…"   About an hour ago   Up About an hour   0.0.0.0:55000->6443/tcp, 0.0.0.0:55001->8404/tcp                  capi-quickstart-lb

# haproxy 컨테이너 정보 확인
docker inspect capi-quickstart-lb | jq
      "WorkingDir": "/",
      "Entrypoint": [
        "haproxy",
        "-W",
        "-db",
        "-f",
        "/usr/local/etc/haproxy/haproxy.cfg"
      ],
      "Ports": {
        "6443/tcp": [
          {
            "HostIp": "0.0.0.0",
            "HostPort": "55000"
          }
        ],
        "8404/tcp": [
          {
            "HostIp": "0.0.0.0",
            "HostPort": "55001"
          }
        ]
      },
      "Networks": {
        "kind": {
          "IPAMConfig": null,
          "Links": null,
          "Aliases": null,
          "MacAddress": "02:42:ac:13:00:03",
          "DriverOpts": null,
          "NetworkID": "e63730b2d6128d69251ba090295bc1308849a051f68f2e5c69146e495ae0059b",
          "EndpointID": "4e47ba9b001ba298eb61aec6b59ed80412c8c89f76cd89a70efe8cd5c636d7ff",
          "Gateway": "172.19.0.1",
          "IPAddress": "172.19.0.3",
          "IPPrefixLen": 16,
          "IPv6Gateway": "fc00:f853:ccd:e793::1",
          "GlobalIPv6Address": "fc00:f853:ccd:e793::3",
          "GlobalIPv6PrefixLen": 64,
          "DNSNames": [
            "capi-quickstart-lb",
            "26e142b6ea42"
          ]

# lb 기능 동작 테스트 
curl -sk https://127.0.0.1:55000/version | jq
{
  "major": "1",
  "minor": "34",
  "emulationMajor": "1",
  "emulationMinor": "34",
  "minCompatibilityMajor": "1",
  "minCompatibilityMinor": "33",
  "gitVersion": "v1.34.3",
  "gitCommit": "df11db1c0f08fab3c0baee1e5ce6efbf816af7f1",
  "gitTreeState": "clean",
  "buildDate": "2025-12-09T14:59:13Z",
  "goVersion": "go1.24.11",
  "compiler": "gc",
  "platform": "linux/arm64"
}


k8s1 cluster-info
Kubernetes control plane is running at https://localhost:55000

# haproxy 설정 확인
docker cp capi-quickstart-lb:/usr/local/etc/haproxy/haproxy.cfg .
cat haproxy.cfg

# 로그 조회
docker logs -f capi-quickstart-lb
[WARNING] 048/053020 (486) : Server kube-apiservers/capi-quickstart-mstjv-xdfcr is DOWN, reason: Layer4 connection problem, info: "SSL handshake failure", check duration: 0ms. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
[WARNING] 048/053045 (486) : Server kube-apiservers/capi-quickstart-mstjv-xdfcr is UP, reason: Layer7 check passed, code: 200, check duration: 12ms. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

k8s1 describe node -l node-role.kubernetes.io/control-plane

# CP 노드 확인
k8s1 get node -owide -l node-role.kubernetes.io/control-plane
NAME                          STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
capi-quickstart-mstjv-6fz6t   Ready    control-plane   71m   v1.34.3   172.19.0.8    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-xdfcr   Ready    control-plane   66m   v1.34.3   172.19.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-xjjj8   Ready    control-plane   71m   v1.34.3   172.19.0.9    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0

# 파드 확인
k8s1 get pod -n kube-system
NAME                                                  READY   STATUS    RESTARTS   AGE
calico-kube-controllers-6fd9cc49d6-74ffb              1/1     Running   0          68m
calico-node-bzzmw                                     1/1     Running   0          67m
calico-node-dxkp2                                     1/1     Running   0          68m
calico-node-gmg9j                                     1/1     Running   0          68m
calico-node-qjlsn                                     1/1     Running   0          68m
calico-node-qsc6d                                     1/1     Running   0          67m
calico-node-x4vsw                                     1/1     Running   0          68m
coredns-66bc5c9577-jclp6                              1/1     Running   0          78m
coredns-66bc5c9577-xstzj                              1/1     Running   0          78m
etcd-capi-quickstart-mstjv-6fz6t                      1/1     Running   0          71m
etcd-capi-quickstart-mstjv-xdfcr                      1/1     Running   0          67m
etcd-capi-quickstart-mstjv-xjjj8                      1/1     Running   0          71m
kube-apiserver-capi-quickstart-mstjv-6fz6t            1/1     Running   0          71m
kube-apiserver-capi-quickstart-mstjv-xdfcr            1/1     Running   0          67m
kube-apiserver-capi-quickstart-mstjv-xjjj8            1/1     Running   0          71m
kube-controller-manager-capi-quickstart-mstjv-6fz6t   1/1     Running   0          71m
kube-controller-manager-capi-quickstart-mstjv-xdfcr   1/1     Running   0          67m
kube-controller-manager-capi-quickstart-mstjv-xjjj8   1/1     Running   0          71m
kube-ops-view-97fd86569-cxb4r                         1/1     Running   0          8m5s
kube-proxy-4ftrm                                      1/1     Running   0          71m
kube-proxy-jh95x                                      1/1     Running   0          67m
kube-proxy-mltm9                                      1/1     Running   0          67m
kube-proxy-rdtbd                                      1/1     Running   0          71m
kube-proxy-tvx6q                                      1/1     Running   0          72m
kube-proxy-xqn48                                      1/1     Running   0          72m
kube-scheduler-capi-quickstart-mstjv-6fz6t            1/1     Running   0          71m
kube-scheduler-capi-quickstart-mstjv-xdfcr            1/1     Running   0          67m
kube-scheduler-capi-quickstart-mstjv-xjjj8            1/1     Running   0          71m

# 
k8s1 get cm,secret,csr -n kube-system
NAME                                                             DATA   AGE
configmap/calico-config                                          4      77m
configmap/coredns                                                1      87m
configmap/extension-apiserver-authentication                     6      87m
configmap/kube-apiserver-legacy-service-account-token-tracking   1      87m
configmap/kube-proxy                                             2      87m
configmap/kube-root-ca.crt                                       1      87m
configmap/kubeadm-config                                         1      87m
configmap/kubelet-config                                         1      87m
NAME                                         TYPE                            DATA   AGE
secret/bootstrap-token-zelvpd                bootstrap.kubernetes.io/token   6      87m
secret/sh.helm.release.v1.kube-ops-view.v1   helm.sh/release.v1              1      16m
NAME                                                      AGE   SIGNERNAME                                    REQUESTOR                 REQUESTEDDURATION   CONDITION
certificatesigningrequest.certificates.k8s.io/csr-gzrrl   76m   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:o2r4g9   <none>              Approved,Issued
certificatesigningrequest.certificates.k8s.io/csr-l4lht   76m   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:ynla7i   <none>              Approved,Issued

# kubeadm 설정 확인
k8s1 get cm -n kube-system kubeadm-config -o yaml
apiVersion: v1
data:
  ClusterConfiguration: |
    apiServer:
      certSANs:
      - localhost
      - 127.0.0.1
      - 0.0.0.0 # 신기하게도 0.0.0.0으로 구성
      - host.docker.internal
    apiVersion: kubeadm.k8s.io/v1beta4
    caCertificateValidityPeriod: 87600h0m0s
    certificateValidityPeriod: 8760h0m0s
    certificatesDir: /etc/kubernetes/pki
    clusterName: capi-quickstart
    controlPlaneEndpoint: 172.19.0.3:6443
    controllerManager: {}
    dns: {}
    encryptionAlgorithm: RSA-2048
    etcd:
      local:
        dataDir: /var/lib/etcd
    featureGates:
      ControlPlaneKubeletLocalMode: true
    imageRepository: registry.k8s.io
    kind: ClusterConfiguration
    kubernetesVersion: v1.34.3
    networking:
      dnsDomain: myk8s-1.local
      podSubnet: 10.10.0.0/16
      serviceSubnet: 10.20.0.0/16
    proxy: {}
    scheduler: {}
kind: ConfigMap
metadata:
  creationTimestamp: "2026-02-18T05:19:32Z"
  name: kubeadm-config
  namespace: kube-system
  resourceVersion: "267"
  uid: 514badaf-f736-415f-bee4-13003674ed7f

# cp 동작 테스트
CTR1=capi-quickstart-mstjv-xdfcr

# 패키지 다운로드 
docker exec -i $CTR1 sh -c "apt update ; apt install tree psmisc -y"
docker exec -i $CTR1 pstree -a

# 컨트롤 플레인 내부에 실행중인 컨테이너 조회
docker exec -i $CTR1 crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                      ATTEMPT             POD ID              POD                                                   NAMESPACE
8a2e397a564ab       0946456496183       About an hour ago   Running             calico-kube-controllers   0                   b5f6a982ae949       calico-kube-controllers-6fd9cc49d6-74ffb              kube-system
8c7cb4cb75103       138784d87c9c5       About an hour ago   Running             coredns                   0                   b6b59811a3c06       coredns-66bc5c9577-xstzj                              kube-system
b5459650ae54f       138784d87c9c5       About an hour ago   Running             coredns                   0                   88442d8352b27       coredns-66bc5c9577-jclp6                              kube-system
cddf4010531d7       c445639cb2880       About an hour ago   Running             calico-node               0                   7d18cabf3211c       calico-node-dxkp2                                     kube-system
51c4b827b3337       4461daf6b6af8       About an hour ago   Running             kube-proxy                0                   c93162b67556f       kube-proxy-4ftrm                                      kube-system
1a5041633dc60       2c5f0dedd21c2       About an hour ago   Running             etcd                      0                   e84e683bc846f       etcd-capi-quickstart-mstjv-xjjj8                      kube-system
dc9eb9df5387a       cf65ae6c8f700       About an hour ago   Running             kube-apiserver            0                   fe484009990fa       kube-apiserver-capi-quickstart-mstjv-xjjj8            kube-system
4b6a6f5d848f7       7ada8ff13e54b       About an hour ago   Running             kube-controller-manager   0                   80456fdcae415       kube-controller-manager-capi-quickstart-mstjv-xjjj8   kube-system
6a5e37f81f009       2f2aa21d34d2d       About an hour ago   Running             kube-scheduler            0                   3dae041afb584       kube-scheduler-capi-quickstart-mstjv-xjjj8            kube-syste

# kubeadm 인증서 조회
docker exec -i $CTR1 kubeadm certs check-expiration
[check-expiration] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[check-expiration] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.
CERTIFICATE                  EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                   Feb 18, 2027 05:26 UTC   364d            ca                      no      
apiserver                    Feb 18, 2027 05:26 UTC   364d            ca                      no      
apiserver-etcd-client        Feb 18, 2027 05:26 UTC   364d            etcd-ca                 no      
apiserver-kubelet-client     Feb 18, 2027 05:26 UTC   364d            ca                      no      
controller-manager.conf      Feb 18, 2027 05:26 UTC   364d            ca                      no      
etcd-healthcheck-client      Feb 18, 2027 05:26 UTC   364d            etcd-ca                 no      
etcd-peer                    Feb 18, 2027 05:26 UTC   364d            etcd-ca                 no      
etcd-server                  Feb 18, 2027 05:26 UTC   364d            etcd-ca                 no      
front-proxy-client           Feb 18, 2027 05:26 UTC   364d            front-proxy-ca          no      
scheduler.conf               Feb 18, 2027 05:26 UTC   364d            ca                      no      
!MISSING! super-admin.conf                                                                    
CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Feb 16, 2036 05:18 UTC   9y              no      
etcd-ca                 Feb 16, 2036 05:18 UTC   9y              no      
front-proxy-ca          Feb 16, 2036 05:18 UTC   9y              no  

# k8s 설정 조회
docker exec -i $CTR1 tree /etc/kubernetes
/etc/kubernetes
|-- admin.conf
|-- controller-manager.conf
|-- kubelet.conf
|-- manifests
|   |-- etcd.yaml
|   |-- kube-apiserver.yaml
|   |-- kube-controller-manager.yaml
|   `-- kube-scheduler.yaml
|-- pki
|   |-- apiserver-etcd-client.crt
|   |-- apiserver-etcd-client.key
|   |-- apiserver-kubelet-client.crt
|   |-- apiserver-kubelet-client.key
|   |-- apiserver.crt
|   |-- apiserver.key
|   |-- ca.crt
|   |-- ca.key
|   |-- etcd
|   |   |-- ca.crt
|   |   |-- ca.key
|   |   |-- healthcheck-client.crt
|   |   |-- healthcheck-client.key
|   |   |-- peer.crt
|   |   |-- peer.key
|   |   |-- server.crt
|   |   `-- server.key
|   |-- front-proxy-ca.crt
|   |-- front-proxy-ca.key
|   |-- front-proxy-client.crt
|   |-- front-proxy-client.key
|   |-- sa.key
|   `-- sa.pub
`-- scheduler.conf
4 directories, 30 files

# 키 확인
docker exec -i $CTR1 tree /etc/kubernetes/pki
/etc/kubernetes/pki
|-- apiserver-etcd-client.crt
|-- apiserver-etcd-client.key
|-- apiserver-kubelet-client.crt
|-- apiserver-kubelet-client.key
|-- apiserver.crt
|-- apiserver.key
|-- ca.crt
|-- ca.key
|-- etcd
|   |-- ca.crt
|   |-- ca.key
|   |-- healthcheck-client.crt
|   |-- healthcheck-client.key
|   |-- peer.crt
|   |-- peer.key
|   |-- server.crt
|   `-- server.key
|-- front-proxy-ca.crt
|-- front-proxy-ca.key
|-- front-proxy-client.crt
|-- front-proxy-client.key
|-- sa.key
`-- sa.pub
2 directories, 22 files

# 인증서 발급자 확인
docker exec -i $CTR1 cat /etc/kubernetes/pki/ca.crt | openssl x509 -text -noout
        Issuer: CN=kubernetes
        Subject: CN=kubernetes

# 스태틱 파드 확인 
docker exec -i $CTR1 tree /etc/kubernetes/manifests
/etc/kubernetes/manifests
|-- etcd.yaml
|-- kube-apiserver.yaml
|-- kube-controller-manager.yaml
`-- kube-scheduler.yaml
1 directory, 4 files

# etcd 상태 확인
docker exec -i $CTR1 tree /var/lib/etcd
/var/lib/etcd
`-- member
    |-- snap
    |   |-- 0000000000000004-0000000000000838.snap
    |   |-- 0000000000000004-0000000000002f49.snap
    |   `-- db
    `-- wal
        |-- 0.tmp
        `-- 0000000000000000-0000000000000000.wal
4 directories, 5 files

# api-server 인증서 확인
docker exec -i $CTR1 cat /etc/kubernetes/pki/apiserver.crt | openssl x509 -text -noout
                DNS:capi-quickstart-mstjv-xjjj8, DNS:host.docker.internal, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.myk8s-1.local, DNS:localhost, IP Address:10.20.0.1, IP Address:172.19.0.9, IP Address:172.19.0.3, IP Address:127.0.0.1, IP Address:0.0.0.0

# dns 설정 확인
k8s1 exec -it -n kube-system deploy/kube-ops-view -- cat /etc/resolv.conf
search kube-system.svc.myk8s-1.local svc.myk8s-1.local myk8s-1.local
nameserver 10.20.0.10
options ndots:5

# kubelet설정 확인
k8s1 get cm -n kube-system kubelet-config -o yaml
    clusterDNS:
    - 10.20.0.10
    clusterDomain: myk8s-1.local
    staticPodPath: /etc/kubernetes/manifests

#
k8s1 get lease -n kube-system
NAME                                   HOLDER                                                                      AGE
apiserver-ba4i3j77wl5xwc46fnx7yspoau   apiserver-ba4i3j77wl5xwc46fnx7yspoau_e12e03db-cdf9-4b4c-a56e-51a43c4f7b9f   80m
apiserver-eecwmgrlkwjmk2awcplswpusuy   apiserver-eecwmgrlkwjmk2awcplswpusuy_6817930f-7442-487c-8c39-88eac7e09943   84m
apiserver-qg532kjf2ziwalneaqrot7dfte   apiserver-qg532kjf2ziwalneaqrot7dfte_1779777a-38b9-4542-9593-efd373eb589e   85m
kube-controller-manager                capi-quickstart-mstjv-xjjj8_a68f4e8d-d9b4-492a-af54-d426e0000332            91m
kube-scheduler                         capi-quickstart-mstjv-6fz6t_2a72c669-8d10-4bb7-88fa-57df23bb2734            91m

docker ps

# api-server 파드 확인
k8s1 get pod -n kube-system -l component=kube-apiserver
NAME                                         READY   STATUS    RESTARTS   AGE
kube-apiserver-capi-quickstart-mstjv-6fz6t   1/1     Running   0          85m
kube-apiserver-capi-quickstart-mstjv-xdfcr   1/1     Running   0          80m
kube-apiserver-capi-quickstart-mstjv-xjjj8   1/1     Running   0          84m

k8s1 describe pod -n kube-system -l component=kube-apiserver
      --etcd-servers=https://127.0.0.1:2379
      --service-cluster-ip-range=10.20.0.0/16
      --service-account-issuer=https://kubernetes.default.svc.myk8s-1.local


# kube-scheduler 확인
k8s1 get pod -n kube-system -l component=kube-scheduler
NAME                                         READY   STATUS    RESTARTS   AGE
kube-scheduler-capi-quickstart-mstjv-6fz6t   1/1     Running   0          86m
kube-scheduler-capi-quickstart-mstjv-xdfcr   1/1     Running   0          81m
kube-scheduler-capi-quickstart-mstjv-xjjj8   1/1     Running   0          85m

k8s1 describe pod -n kube-system -l component=kube-scheduler
      kube-scheduler
      --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
      --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
      --bind-address=127.0.0.1
      --kubeconfig=/etc/kubernetes/scheduler.conf
      --leader-elect=true

docker exec -i $CTR1 cat /etc/kubernetes/scheduler.conf | grep server
    server: https://172.19.0.9:6443

# kube-controller-manager 확인
k8s1 get pod -n kube-system -l component=kube-controller-manager
NAME                                                  READY   STATUS    RESTARTS   AGE
kube-controller-manager-capi-quickstart-mstjv-6fz6t   1/1     Running   0          87m
kube-controller-manager-capi-quickstart-mstjv-xdfcr   1/1     Running   0          82m
kube-controller-manager-capi-quickstart-mstjv-xjjj8   1/1     Running   0          86m

k8s1 describe pod -n kube-system -l component=kube-controller-manager
      kube-controller-manager
      --allocate-node-cidrs=true
      --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
      --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
      --bind-address=127.0.0.1
      --client-ca-file=/etc/kubernetes/pki/ca.crt
      --cluster-cidr=10.10.0.0/16
      --cluster-name=capi-quickstart
      --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
      --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
      --controllers=*,bootstrapsigner,tokencleaner
      --kubeconfig=/etc/kubernetes/controller-manager.conf
      --leader-elect=true
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
      --root-ca-file=/etc/kubernetes/pki/ca.crt
      --service-account-private-key-file=/etc/kubernetes/pki/sa.key
      --service-cluster-ip-range=10.20.0.0/16
      --use-service-account-credentials=true

# etcd 확인
k8s1 get pod -n kube-system -l component=etcd
NAME                               READY   STATUS    RESTARTS   AGE
etcd-capi-quickstart-mstjv-6fz6t   1/1     Running   0          87m
etcd-capi-quickstart-mstjv-xdfcr   1/1     Running   0          82m
etcd-capi-quickstart-mstjv-xjjj8   1/1     Running   0          86m

k8s1 describe pod -n kube-system -l component=etcd
    Command:
      etcd
      --advertise-client-urls=https://172.19.0.9:2379
      --cert-file=/etc/kubernetes/pki/etcd/server.crt
      --client-cert-auth=true
      --data-dir=/var/lib/etcd
      --feature-gates=InitialCorruptCheck=true
      --initial-advertise-peer-urls=https://172.19.0.9:2380
      --initial-cluster=capi-quickstart-mstjv-6fz6t=https://172.19.0.8:2380,capi-quickstart-mstjv-xjjj8=https://172.19.0.9:2380,capi-quickstart-mstjv-8w2bs=https://172.19.0.4:2380
      --initial-cluster-state=existing
      --key-file=/etc/kubernetes/pki/etcd/server.key
      --listen-client-urls=https://127.0.0.1:2379,https://172.19.0.9:2379
      --listen-metrics-urls=http://127.0.0.1:2381
      --listen-peer-urls=https://172.19.0.9:2380
      --name=capi-quickstart-mstjv-xjjj8
      --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
      --peer-client-cert-auth=true
      --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
      --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
      --snapshot-count=10000
      --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
      --watch-progress-notify-interval=5s


docker exec -it $CTR1 bash
find / -name etcdctl
/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/63/fs/usr/local/bin/etcdctl
/run/containerd/io.containerd.runtime.v2.task/k8s.io/1a5041633dc604b6ce2efe3856ea276402ba9ea843d33a5410f46764bfd639bd/rootfs/usr/local/bin/etcdctl

# 심볼링 링크 생성
ln -s /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/63/fs/usr/local/bin/etcdctl /usr/local/bin/

# etcdctl 확인
etcdctl version
etcdctl version: 3.6.5
API version: 3.6

# 환경변수 정의
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 

# etcd 상태 확인
etcdctl endpoint status -w table
+------------------------+------------------+---------+-----------------+---------+--------+-----------------------+-------+-----------+------------+-----------+------------+--------------------+--------+--------------------------+-------------------+
|        ENDPOINT        |        ID        | VERSION | STORAGE VERSION | DB SIZE | IN USE | PERCENTAGE NOT IN USE | QUOTA | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS | DOWNGRADE TARGET VERSION | DOWNGRADE ENABLED |
+------------------------+------------------+---------+-----------------+---------+--------+-----------------------+-------+-----------+------------+-----------+------------+--------------------+--------+--------------------------+-------------------+
| https://127.0.0.1:2379 | 3b44d0f7b7e1737c |   3.6.5 |           3.6.0 |  8.7 MB | 2.4 MB |                   73% |   0 B |     false |      false |         4 |      18084 |              18084 |        |                          |             false |
+------------------------+------------------+---------+-----------------+---------+--------+-----------------------+-------+-----------+------------+-----------+------------+--------------------+--------+--------------------------+-------------------+

# etcd 멤버 리스트 조회
etcdctl member list -w table
+------------------+---------+-----------------------------+-------------------------+-------------------------+------------+
|        ID        | STATUS  |            NAME             |       PEER ADDRS        |      CLIENT ADDRS       | IS LEARNER |
+------------------+---------+-----------------------------+-------------------------+-------------------------+------------+
| 2da83b32d9cbb4df | started | capi-quickstart-mstjv-6fz6t | https://172.19.0.8:2380 | https://172.19.0.8:2379 |      false |
| 3b44d0f7b7e1737c | started | capi-quickstart-mstjv-xjjj8 | https://172.19.0.9:2380 | https://172.19.0.9:2379 |      false |
| ea1eeb5ccaa2ff45 | started | capi-quickstart-mstjv-xdfcr | https://172.19.0.4:2380 | https://172.19.0.4:2379 |      false |
+------------------+---------+-----------------------------+-------------------------+-------------------------+------------+

# bash 종료
exit

# mansgerment 클러스터 시크릿 확인
k get secret -l cluster.x-k8s.io/cluster-name=capi-quickstart
NAME                                     TYPE                      DATA   AGE
capi-quickstart-ca                       cluster.x-k8s.io/secret   2      97m
capi-quickstart-etcd                     cluster.x-k8s.io/secret   2      97m
capi-quickstart-kubeconfig               cluster.x-k8s.io/secret   1      97m
capi-quickstart-md-0-xtlgs-6pmbd-nr8qx   cluster.x-k8s.io/secret   2      91m
capi-quickstart-md-0-xtlgs-6pmbd-pnqhd   cluster.x-k8s.io/secret   2      91m
capi-quickstart-md-0-xtlgs-6pmbd-qr5kr   cluster.x-k8s.io/secret   2      86m
capi-quickstart-mstjv-6fz6t              cluster.x-k8s.io/secret   2      91m
capi-quickstart-mstjv-xdfcr              cluster.x-k8s.io/secret   2      86m
capi-quickstart-mstjv-xjjj8              cluster.x-k8s.io/secret   2      90m
capi-quickstart-proxy                    cluster.x-k8s.io/secret   2      97m
capi-quickstart-sa                       cluster.x-k8s.io/secret   2      97m


# 워크로드 클러스터의 kubeconfig 확인
k get secret capi-quickstart-kubeconfig -o jsonpath='{.data.value}' | base64 -d
    server: https://172.19.0.3:6443
  name: capi-quickstart
contexts:
- context:
    cluster: capi-quickstart
    user: capi-quickstart-admin
  name: capi-quickstart-admin@capi-quickstart
current-context: capi-quickstart-admin@capi-quickstart
kind: Config
users:
- name: capi-quickstart-admin
  user:

# cloud-init config
k get secret capi-quickstart-mstjv-6fz6t -o jsonpath='{.data.value}' | base64 -d
write_files:
-   path: /etc/kubernetes/pki/ca.crt
    owner: root:root
    permissions: '0640'
    content: |
      -----BEGIN CERTIFICATE-----
      -----END CERTIFICATE-----
-   path: /etc/kubernetes/pki/ca.key
    owner: root:root
    permissions: '0600'
    content: |
      -----BEGIN RSA PRIVATE KEY----
      -----END RSA PRIVATE KEY-----
-   path: /etc/kubernetes/pki/etcd/ca.crt
    owner: root:root
    permissions: '0640'
    content: |
      -----BEGIN CERTIFICATE-----
      -----END CERTIFICATE-----
-   path: /etc/kubernetes/pki/etcd/ca.key
    owner: root:root
    permissions: '0600'
    content: |
      -----BEGIN RSA PRIVATE KEY-----
      -----END RSA PRIVATE KEY-----
-   path: /etc/kubernetes/pki/front-proxy-ca.crt
    owner: root:root
    permissions: '0640'
    content: |
      -----BEGIN CERTIFICATE-----
      -----END CERTIFICATE-----
-   path: /etc/kubernetes/pki/front-proxy-ca.key
    owner: root:root
    permissions: '0600'
    content: |
      -----BEGIN RSA PRIVATE KEY-----
      -----END RSA PRIVATE KEY-----    
-   path: /etc/kubernetes/pki/sa.pub
    owner: root:root
    permissions: '0640'
    content: |
      -----BEGIN PUBLIC KEY-----
      -----END PUBLIC KEY-----
-   path: /etc/kubernetes/pki/sa.key
    owner: root:root
    permissions: '0600'
    content: |
      -----BEGIN RSA PRIVATE KEY-----
      -----END RSA PRIVATE KEY-----

-   path: /run/kubeadm/kubeadm-join-config.yaml
    owner: root:root
    permissions: '0640'
    content: |
      apiVersion: kubeadm.k8s.io/v1beta4
      controlPlane:
        localAPIEndpoint: {}
      discovery:
        bootstrapToken:
          apiServerEndpoint: 172.19.0.3:6443
          caCertHashes:
          - sha256:5ed7f5f8e4574d8dd2c13418272599f186ab42448fa3a49325e7e570f48c7ff8
          token: t6ce1o.wkyg0xd1di0itgau
      kind: JoinConfiguration
      nodeRegistration:
        kubeletExtraArgs:
        - name: eviction-hard
          value: nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%
        taints: null

-   path: /run/cluster-api/placeholder
    owner: root:root
    permissions: '0640'
    content: "This placeholder file is used to create the /run/cluster-api sub directory in a way that is compatible with both Linux and Windows (mkdir -p /run/cluster-api does not work with Windows)"

runcmd:
  - kubeadm join --config /run/kubeadm/kubeadm-join-config.yaml  && echo success > /run/cluster-api/bootstrap-success.complete
```


## CAPI 노드 관리
```sh
# 공용 모니터링 도구 : kube-ops-view
k8s1 -n kube-system port-forward svc/kube-ops-view 8080:8080 &
haproxy web stats
kubectl --kubeconfig=capi-quickstart.kubeconfig get node -w
watch -d kubectl --kubeconfig=capi-quickstart.kubeconfig get node
watch -d "docker ps ; echo ; clusterctl describe cluster capi-quickstart"
```

### k8s 버전 업그레이드
```sh
kubectl get cluster
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE    VERSION
capi-quickstart   quick-start    True        3            3              3               3           3             3              Provisioned   103m   v1.34.3

# 컨트롤 플레인이 추기되면서 컨트롤 플레인순으로 점진적 업데이트 수행
# 6대 노드 기준 CP 3대, 워커 3대 업데이트 약 5분 ~ 소요 
kubectl patch cluster capi-quickstart --type merge -p '{"spec":{"topology":{"version":"v1.35.0"}}}'

# 노드 조회
k8s1 get node
NAME                                     STATUS   ROLES           AGE     VERSION
capi-quickstart-md-0-xtlgs-d6hmn-flflp   Ready    <none>          110s    v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-k8f2v   Ready    <none>          2m32s   v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-xcj4g   Ready    <none>          69s     v1.35.0
capi-quickstart-mstjv-dvvg2              Ready    control-plane   4m24s   v1.35.0
capi-quickstart-mstjv-n5t9s              Ready    control-plane   5m13s   v1.35.0
capi-quickstart-mstjv-rrtnj              Ready    control-plane   3m3s    v1.35.0

# 머신을 불변 형태로 관리하기 떄문에, 기존 컨테이너를 활용하지 않고 새로운 컨테이너가 생성된 것을 확인할수 있다.
docker ps
CONTAINER ID   IMAGE                                COMMAND                   CREATED              STATUS              PORTS                                                             NAMES
7dddf8444dc4   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   About a minute ago   Up About a minute                                                                     capi-quickstart-md-0-xtlgs-d6hmn-xcj4g
5c5b074b2f05   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   2 minutes ago        Up 2 minutes                                                                          capi-quickstart-md-0-xtlgs-d6hmn-flflp
58bb2c6daa6a   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   2 minutes ago        Up 2 minutes                                                                          capi-quickstart-md-0-xtlgs-d6hmn-k8f2v
0e2e88021d7f   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   3 minutes ago        Up 3 minutes        127.0.0.1:55011->6443/tcp                                         capi-quickstart-mstjv-rrtnj
fc5c56326e48   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   5 minutes ago        Up 5 minutes        127.0.0.1:55010->6443/tcp                                         capi-quickstart-mstjv-dvvg2
58c0bcce5986   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   5 minutes ago        Up 5 minutes        127.0.0.1:55009->6443/tcp                                         capi-quickstart-mstjv-n5t9s
26e142b6ea42   kindest/haproxy:v20230606-42a2262b   "haproxy -W -db -f /…"   2 hours ago          Up 2 hours          0.0.0.0:55000->6443/tcp, 0.0.0.0:55001->8404/tcp                  capi-quickstart-lb
9b88e3a6da34   kindest/node:v1.35.0                 "/usr/local/bin/entr…"   2 hours ago          Up 2 hours          0.0.0.0:30000-30001->30000-30001/tcp, 127.0.0.1:56922->6443/tcp   myk8s-control-plane

# haproxy.cfg 복사
docker cp capi-quickstart-lb:/usr/local/etc/haproxy/haproxy.cfg .

# 컨트롤플레인 ip 주소 자동 업데이트 반영
cat haproxy.cfg
  server capi-quickstart-mstjv-dvvg2 172.19.0.8:6443 weight 100 check check-ssl verify none resolvers docker resolve-prefer ipv4
  server capi-quickstart-mstjv-n5t9s 172.19.0.10:6443 weight 100 check check-ssl verify none resolvers docker resolve-prefer ipv4
  server capi-quickstart-mstjv-rrtnj 172.19.0.9:6443 weight 100 check check-ssl verify none resolvers docker resolve-prefer ipv4
```

### 워커 노드 확장
```sh
# 워크로드 클러스터 확인
kubectl get cluster
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE    VERSION
capi-quickstart   quick-start    True        3            3              3               3           3             3              Provisioned   111m   v1.35.0

# 노드 3대 -> 4대 증가
kubectl patch cluster capi-quickstart --type merge -p '{
  "spec": {
    "topology": {
      "workers": {
        "machineDeployments": [
          {
            "class": "default-worker",
            "name": "md-0",
            "replicas": 4
          }
        ]
      }
    }
  }
}'

# 워크로드 클러스터 확인
kubectl get cluster
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE    VERSION
capi-quickstart   quick-start    False       3            3              3               4           3             4              Provisioned   112m   v1.35.0

# 노드 조회
k8s1 get node
NAME                                     STATUS   ROLES           AGE     VERSION
capi-quickstart-md-0-xtlgs-d6hmn-f9d42   Ready    <none>          25s     v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-flflp   Ready    <none>          5m21s   v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-k8f2v   Ready    <none>          6m3s    v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-xcj4g   Ready    <none>          4m40s   v1.35.0
capi-quickstart-mstjv-dvvg2              Ready    control-plane   7m55s   v1.35.0
capi-quickstart-mstjv-n5t9s              Ready    control-plane   8m44s   v1.35.0
capi-quickstart-mstjv-rrtnj              Ready    control-plane   6m34s   v1.35.0

# 복구 
kubectl patch cluster capi-quickstart --type merge -p '{
  "spec": {
    "topology": {
      "workers": {
        "machineDeployments": [
          {
            "class": "default-worker",
            "name": "md-0",
            "replicas": 3
          }
        ]
      }
    }
  }
}'


# 워크로드 클러스터 확인
kubectl get cluster
NAME              CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE    VERSION
capi-quickstart   quick-start    True        3            3              3               3           3             3              Provisioned   113m   v1.35.0
```

### MachineDeployment 추가
```sh
# 워커 노드 개수 확인
kubectl get cluster capi-quickstart -o jsonpath='{.spec.topology.workers}' | jq
{
  "machineDeployments": [
    {
      "class": "default-worker",
      "name": "md-0",
      "replicas": 3
    }
  ]
}

# 새로운 machineDeployments. 즉 워커 노드 그룹 정의
kubectl patch cluster capi-quickstart --type json --patch '[{"op": "add", "path": "/spec/topology/workers/machineDeployments/-",  "value": {"name": "second-deployment", "replicas": 1, "class": "default-worker"} }]'

# 노드 조회
k8s1 get nodes -owide
NAME                                     STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
capi-quickstart-md-0-xtlgs-d6hmn-flflp   Ready    <none>          7m45s   v1.35.0   172.19.0.6    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-d6hmn-k8f2v   Ready    <none>          8m27s   v1.35.0   172.19.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-d6hmn-xcj4g   Ready    <none>          7m4s    v1.35.0   172.19.0.5    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-dvvg2              Ready    control-plane   10m     v1.35.0   172.19.0.8    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-n5t9s              Ready    control-plane   11m     v1.35.0   172.19.0.10   <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-rrtnj              Ready    control-plane   8m58s   v1.35.0   172.19.0.9    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0

# 새 machineDeployments 확인
kubectl get cluster capi-quickstart -o jsonpath='{.spec.topology.workers}' | jq
{
  "machineDeployments": [
    {
      "class": "default-worker",
      "name": "md-0",
      "replicas": 3
    },
    {
      "class": "default-worker",
      "name": "second-deployment",
      "replicas": 1
    }
  ]
}

# 노드 조회
k8s1 get nodes
NAME                                                  STATUS   ROLES           AGE     VERSION
capi-quickstart-md-0-xtlgs-d6hmn-flflp                Ready    <none>          8m40s   v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-k8f2v                Ready    <none>          9m22s   v1.35.0
capi-quickstart-md-0-xtlgs-d6hmn-xcj4g                Ready    <none>          7m59s   v1.35.0
capi-quickstart-mstjv-dvvg2                           Ready    control-plane   11m     v1.35.0
capi-quickstart-mstjv-n5t9s                           Ready    control-plane   12m     v1.35.0
capi-quickstart-mstjv-rrtnj                           Ready    control-plane   9m53s   v1.35.0
capi-quickstart-second-deployment-j7pmx-2nm9c-w5gvd   Ready    <none>          52s     v1.35.0
```

### 워크로드 클러스터의 컨트를 플레인 확장
```sh
# 현재 컨트롤 플레인 개수 확인
kubectl get cluster capi-quickstart -o jsonpath='{.spec.topology.controlPlane}' | jq
{
  "replicas": 3
}

# 3대에서 5대로 스케일 아웃
kubectl patch cluster capi-quickstart --type json --patch '[{"op": "replace", "path": "/spec/topology/controlPlane/replicas",  "value": 5}]'

# 노드 조회
k8s1 get nodes -owide
NAME                                                  STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
capi-quickstart-md-0-xtlgs-d6hmn-flflp                Ready    <none>          12m     v1.35.0   172.19.0.6    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-d6hmn-k8f2v                Ready    <none>          13m     v1.35.0   172.19.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-md-0-xtlgs-d6hmn-xcj4g                Ready    <none>          11m     v1.35.0   172.19.0.5    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-cfwsv                           Ready    control-plane   2m19s   v1.35.0   172.19.0.11   <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-csjll                           Ready    control-plane   79s     v1.35.0   172.19.0.12   <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-dvvg2                           Ready    control-plane   15m     v1.35.0   172.19.0.8    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-n5t9s                           Ready    control-plane   15m     v1.35.0   172.19.0.10   <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-mstjv-rrtnj                           Ready    control-plane   13m     v1.35.0   172.19.0.9    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0
capi-quickstart-second-deployment-j7pmx-2nm9c-w5gvd   Ready    <none>          4m43s   v1.35.0   172.19.0.7    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.2.0

# 현재 컨트롤 플레인 개수 확인
kubectl get cluster capi-quickstart -o jsonpath='{.spec.topology.controlPlane}' | jq
{
  "replicas": 5
}

# haproxy에서 CP 상태 확인
# 3대에서 5대로 증가
open http://localhost:55001/stats


# 워크로드 클러스터 삭제 
kubectl delete cluster capi-quickstart && docker ps
# 매니지먼트 클러스터 kind 삭제
kind delete cluster --name myk8s
```

[^1]: https://cluster-api.sigs.k8s.io/introduction
[^2]: https://cluster-api.sigs.k8s.io/clusterctl/commands/generate-cluster