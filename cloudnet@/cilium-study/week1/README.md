## [Cilium Study 1기] 1주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 1주차 스터디에 대한 정리 글입니다. 

### Cilium
eBPF 기반의 고성능 네트워킹, 멀티 클러스터, 관측가능성, 보안을 제공하는 k8s CNI 플러그인이다.

### eBPF(extended Berkeley Packet Filter)  
기존 리눅스 커널을 변경하는 방식은 다음과 같다. 첫 번째의 경우에는 시간이 얼마나 걸릴지 모른다는 점 그리고 두 번째는 지속적인 운영 관리가 필요하다는 불편함을 가진다. 이러한 문제점을 해결하고자 등장한 기술이 eBPF이다. 리눅스 커널에 대한 소스 코드 변경이나 모듈를 적재하지 않으면서도 리눅스 커널에 대해 동적으로 기능을 추가할 수가 있다. 

1. 커널 소스코드 변경 후 기여하는 방식
2. 커널 모듈을 직접 수정하여 운영하는 방식

eBPF가 이러한 동작이 가능한 이유  
eBPF 프로그램이 이벤트 기반으로 동작하기 때문이다. 커널 또는 애플리케이션에서 특정 훅 이벤트가 실행될 때 실행된다. 훅의 종류로는 시스템콜, 함수 진입 및 종료, 커널 tracepoint, 네트워크 이벤트등이 존재한다. 이러한 방식 덕분에 네트워킹, 관측가능성, 트레이싱, 보안과 같은 다양한 분야에 활용이 가능하다.

![c](https://ebpf.io/static/b4f7d64d4d04806a1de60126926d5f3a/12151/syscall-hook.png)

### 왜 cilium일까
기존에의 패킷을 처리하는 과정은 굉장히 복잡하다. eBPF는 왼쪽의 네트워크 처리하는 방식에서 오른쪽과 같이 네트워크 패킷에 대해 훅을 통해 패킷을 처리함으로써 뛰어난 성능을 제공한다. 기존의 IPtables이 가진 문제점인 새로운 서비스를 생성하게 된다면 모든 정책을 재구성해야 한다는 단점을 가지고 있다. 이는 O(n) 시간복잡도를 가지게 되며, 또한 서비스 수가 많아지게 될 경우 성능에 대한 문제도 가지고 있다.

![c](https://cilium.io/static/7b77faac1700b51b5612abb7ec0c8f40/0bb32/ebpf_hostrouting.png)

### Cilium 설치
Cilium을 활용하기 위해서는 여러 요구 사항을 충족해야 한다.

**권한** 
- CAP_SYS_ADMIN 요구

**마운트된 파일 시스템**
만일 마운트되어 있지 않더라도 cilium이 자동으로 마운트한다. 
```sh
# 마운트 조회
mount | grep /sys/fs/bpf
bpf on /sys/fs/bpf type bpf (rw,nosuid,nodev,noexec,relatime,mode=700)

# 노드 실행 시 자동 마운트
vi /etc/fstab
bpffs                      /sys/fs/bpf             bpf     defaults 0 0
```

**고급 기능에 필요한 커널 버전**
| Cilium Feature                                           | Minimum Kernel Version |
|----------------------------------------------------------|-------------------------|
| WireGuard Transparent Encryption                         | >= 5.6                  |
| Full support for Session Affinity                        | >= 5.7                  |
| BPF-based proxy redirection                              | >= 5.7                  |
| Socket-level LB bypass in pod netns                      | >= 5.7                  |
| L3 devices                                               | >= 5.8                  |
| BPF-based host routing                                   | >= 5.10                 |
| Multicast Support in Cilium (Beta) (AMD64)               | >= 5.10                 |
| IPv6 BIG TCP support                                     | >= 5.19                 |
| Multicast Support in Cilium (Beta) (AArch64)             | >= 6.0                  |
| IPv4 BIG TCP support                                     | >= 6.3                  |

**컨테이너 이미지 실행 시 시스템 요구 사항**
- AMD64 또는 AArch64 아키텍처
- 리눅스 커널 5.4 or 레드햇 계열의 경우 4.18

**요구하는 커널 모듈**
```sh
arch
aarch64

uname -r
6.8.0-53-generic

# 기본 요구 사항
grep -E 'CONFIG_BPF|CONFIG_BPF_SYSCALL|CONFIG_NET_CLS_BPF|CONFIG_BPF_JIT|CONFIG_NET_CLS_ACT|CONFIG_NET_SCH_INGRESS|CONFIG_CRYPTO_SHA1|CONFIG_CRYPTO_USER_API_HASH|CONFIG_CGROUPS|CONFIG_CGROUP_BPF|CONFIG_PERF_EVENTS|CONFIG_SCHEDSTATS' /boot/config-$(uname -r)
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_NET_CLS_BPF=m
CONFIG_NET_CLS_ACT=y
CONFIG_NET_SCH_INGRESS=m
CONFIG_CRYPTO_SHA1=y
CONFIG_CRYPTO_USER_API_HASH=m
CONFIG_CGROUPS=y
CONFIG_CGROUP_BPF=y
CONFIG_PERF_EVENTS=y
CONFIG_SCHEDSTATS=y

# 만일 BPF Masquerading를 사용하지 않는 경우에는 다음 커널 옵션이 필요하다.
# 하단의 배포 과정에서는 BPF를 사용할 예정이라 필요하지 않음
CONFIG_NETFILTER_XT_SET=m
CONFIG_IP_SET=m
CONFIG_IP_SET_HASH_IP=m
CONFIG_NETFILTER_XT_MATCH_COMMENT=m

# Requirements for Tunneling and Routing
grep -E 'CONFIG_VXLAN=y|CONFIG_VXLAN=m|CONFIG_GENEVE=y|CONFIG_GENEVE=m|CONFIG_FIB_RULES=y' /boot/config-$(uname -r)
CONFIG_VXLAN=y
CONFIG_GENEVE=y
CONFIG_FIB_RULES=y

# Requirements for L7 and FQDN Policies
grep -E 'CONFIG_NETFILTER_XT_TARGET_TPROXY|CONFIG_NETFILTER_XT_TARGET_MARK|CONFIG_NETFILTER_XT_TARGET_CT|CONFIG_NETFILTER_XT_MATCH_MARK|CONFIG_NETFILTER_XT_MATCH_SOCKET' /boot/config-$(uname -r)
CONFIG_NETFILTER_XT_TARGET_TPROXY=m
CONFIG_NETFILTER_XT_TARGET_MARK=m
CONFIG_NETFILTER_XT_TARGET_CT=m
CONFIG_NETFILTER_XT_MATCH_MARK=m
CONFIG_NETFILTER_XT_MATCH_SOCKET=m

# Requirements for Netkit Device Mode
grep -E 'CONFIG_NETKIT=y|CONFIG_NETKIT=m' /boot/config-$(uname -r)
CONFIG_NETKIT=y
```

**flannel 리소스 제거**
```sh
# 다음 작업들은 모든 노드에서 수행해야 한다
# 기존 CNI 제거하기 
helm uninstall -n kube-flannel flannel

# vnic 제거 
ip link del flannel.1
ip link del cni0

# kube-proxy 리소스 제거 
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy

# kube, flannel에 대한 iptables 정책 제거하기
iptables-save | grep -v KUBE | grep -v FLANNEL | iptables-restore

# iptables 정책 조회
iptables-save

# 기존에 flannel가 IP를 할당한 파드에 대해서 재시작함으로써 새롭게 ip를 할당해야 한다.
```

만일 기존에 CNI가 설치되어 있다면 다음 과정을 수행해야 한다. CNI가 설치되어 있지 않다면 바로 cilium 설치로 넘어가도 된다. flannel이 생성한 기존 리소스를 제거해야 cilium이 정상적으로 동작한다. 

**Cilium 배포**
```sh
# helm으로 cilium 설치
helm repo add cilium https://helm.cilium.io/

helm install cilium cilium/cilium --version 1.17.5 --namespace kube-system \
# kube-proxy가 api-server에 대한 정보를 알고 있었지만 kube-proxy가 없기 때문에 api-server 주소를 명시해줘야 한다. 
--set k8sServiceHost=192.168.10.100 --set k8sServicePort=6443 \
# kube-proxy를 대체한다.
--set kubeProxyReplacement=true \
# 파드 간에 통신하는 방식을 native로 사용한다. native 외에는 Vxlan(기본값) or geneve이 있으며 AWS, Google 클라우드마다 구성 방식이 다르다.
--set routingMode=native \
--set autoDirectNodeRoutes=true \
# Pod IP CIRD를 cilium이 대신 관리한다. 기존에는 k8s가 파드 CIDR를 관리했다.
--set ipam.mode="cluster-pool" \
# Pod IP CIRD 정의
--set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} \
# SNAT 없이 통신하는 대역대를 지정한다.
--set ipv4NativeRoutingCIDR=172.20.0.0/16 \
# 호스트 노드의 파드에 개별 라우팅 설정
--set endpointRoutes.enabled=true \
# Conntrack 관련된 Iptable 정책 생성하지 않는다. 대신 eBPF로 통신한다. 
--set installNoConntrackIptablesRules=true \
# SNAT도 eBPF가 처리한다.
--set bpf.masquerade=true \
--set ipv6.enabled=false

kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium-dbg status --verbose
```

**Pod CIDR 변화 확인하기**
```sh
# kube-controller에 대한 Pod CIDR 및 SVC CIDR 조회
kubectl describe pod -n kube-system kube-controller-manager-k8s-ctr
Command:
    kube-controller-manager
    --allocate-node-cidrs=true
    --cluster-cidr=10.244.0.0/16
    --service-cluster-ip-range=10.96.0.0/16

# k8s가 괸라하는 Pod CIDR 조회
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
k8s-ctr 10.244.0.0/24
k8s-w1  10.244.1.0/24
k8s-w2  10.244.2.0/24

# k8s가 괸리하는 pod CIDR와 다른 IP 대역을 할당받은 것을 확인할 수가 있다.
kubectl get pod -o wide
curl-pod   1/1     Running   0          13m   172.20.2.205   k8s-ctr   <none>           <none>

# cilium 노드 IP 출력 
kubectl get ciliumnodes

# 노드 별 Pod CIDR 출력
kubectl get ciliumnodes -o json | grep podCIDRs -A2
                    "podCIDRs": [
                        "172.20.2.0/24"
                    ],
--
                    "podCIDRs": [
                        "172.20.1.0/24"
                    ],
--
                    "podCIDRs": [
                        "172.20.0.0/24"
                    ],

# svc는 동일한 CIDR를 가진다.
kubectl get svc
NAME         TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
my-nginx     ClusterIP   10.96.67.78   <none>        80/TCP    2s

# pod 배포
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webpod
spec:
  replicas: 2
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
  type: ClusterIP
---
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  labels:
    app: curl
spec:
  nodeName: k8s-ctr
  containers:
  - name: curl
    image: nicolaka/netshoot
    command: ["tail"]
    args: ["-f", "/dev/null"]
  terminationGracePeriodSeconds: 0
EOF

# 파드간 통신 확인 
kubectl exec -it curl-pod -- curl webpod | grep Hostname

# 파드에 대한 정보 출력 
kubectl get ciliumendpoints -o wide
NAME                        SECURITY IDENTITY   INGRESS ENFORCEMENT   EGRESS ENFORCEMENT   ENDPOINT STATE   IPV4           IPV6
curl-pod                    21894                                                          ready            172.20.2.23
my-nginx-77b9c67898-dhffh   7617                                                           ready            172.20.0.218
my-nginx-77b9c67898-lh4j8   7617                                                           ready            172.20.1.85
webpod-84755789dd-j9xr8     19327                                                          ready            172.20.1.143
webpod-84755789dd-stlss     19327                                                          ready            172.20.0.147

# 특정 노드에서 실행 중인 cilium agnet 상태 조회 및 검사
# 실행한 명령어는 cilium 이지만 cilium 명령어가 아닌 cilium-dbg가 실행된다.
kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium  
CLI for interacting with the local Cilium Agent  
Usage:
cilium-dbg [command]

# 파드에 대한 정보 상세하게 출력한다.
# ctr 노드에서 수행한 결과 172.20.2.0/24에 해당 파드 정보만 출력된다. 
# 이 경우에는 해당 명령어를 수행하는 노드에 실행 중인 파드에 대한 정보만을 출력한다.
kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium-dbg endpoint list
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                              IPv6   IPv4           STATUS
           ENFORCEMENT        ENFORCEMENT
865        Disabled           Disabled          21894      k8s:app=curl                                                                    172.20.2.23    ready
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
2997       Disabled           Disabled          4          reserved:health                                                                 172.20.2.242   ready
4079       Disabled           Disabled          1          k8s:node-role.kubernetes.io/control-plane                                                      ready
                                                           k8s:node.kubernetes.io/exclude-from-external-load-balancers
                                                           reserved:host

# 모든 노드에 대한 파드 정보 출력
for pod in $(kubectl get pods -n kube-system -l k8s-app=cilium -o name); do   echo "=== $pod ===";   kubectl exec -n kube-system $pod -c cilium-agent -- cilium-dbg endpoint list; done
```

**Cilium CLI 설치**
```sh
# cil 설치
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

# cilium 배포 상태 조회
cilium status

# cilium 설정 출력 
cilium config view
kubectl get cm -n kube-system cilium-config -o json | jq

# cilium 설정 변경 
cilium config set debug true && watch kubectl get pod -A

kubectl exec -n kube-system -c cilium-agent -it ds/cilium -- cilium-dbg config
kubectl exec -n kube-system -c cilium-agent -it ds/cilium -- cilium-dbg status --verbose
```

### cilium 구성 요소 
![componet](https://docs.cilium.io/en/stable/_images/cilium-arch.png)

Cilium 
- Agent
  - 데몬셋으로 k8s api 구성에 대해 네트워킹, 네트워킹 정책, 서비스 로드밸런싱, 가시성 및 모니터링을 반영한다.
- Debug Clinet(CLI)
  - `cilium-dbg`는 동일한 노드에서 실행 중인 cilium 에이전트와 rest api로 상호 작용한다. Cilium 에이전트에 대한 상태를 조사하고 eBPF 맵에 액세스가 가능하다. `cilium` 명령어와 명백히 다르며, 차이점으로 `cilium` 명령어는 k8s api와 kubeconfig를 통해 원격으로 액세스하기 위함이라면, `cilium-dbg`는 보다 특정 노드에서 발생되는 원인을 분석하기 위함이다.
- Operator
  - k8s 클러스터에 대해 논리적으로 한 번에 처리해야 하는 임무를 처리한다.

Hubble
- Server 
- Relay
- CLI
- GUI

Data Store
- Kubernetes CRDs
  - 데이터를 저장하고 상태를 전파하기 위해 k8s CRD를 사용한다. k8s에 의해 클러스터 구성 요소에 대해 전달한다. 
- etcd(Key-Value Store)
  - k8s CRD로 충분하지만 키-값 저장소를 사용한다면 더욱 효율적으로 클러스터를 확장할 수 있다.

### 파드 정보 조회
```sh
# 단축키 지정
export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w2  -o jsonpath='{.items[0].metadata.name}')
echo $CILIUMPOD0 $CILIUMPOD1 $CILIUMPOD2

alias c0="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium"
alias c1="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium"
alias c2="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- cilium"

alias c0bpf="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- bpftool"
alias c1bpf="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- bpftool"
alias c2bpf="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- bpftool"



kubectl get pod -owide
kubectl get svc,ep my-nginx
NAME                        READY   STATUS    RESTARTS   AGE     IP             NODE      NOMINATED NODE   READINESS GATES
curl-pod                    1/1     Running   0          3h4m    172.20.2.23    k8s-ctr   <none>           <none>
my-nginx-77b9c67898-8h7nr   1/1     Running   0          71m     172.20.0.221   k8s-w2    <none>           <none>
my-nginx-77b9c67898-bmk4c   1/1     Running   0          71m     172.20.0.213   k8s-w2    <none>           <none>
my-nginx-77b9c67898-dhffh   1/1     Running   0          3h31m   172.20.0.218   k8s-w2    <none>           <none>
webpod-697b545f57-mbghv     1/1     Running   0          99m     172.20.1.99    k8s-w1    <none>           <none>
webpod-697b545f57-vfrr9     1/1     Running   0          99m     172.20.0.247   k8s-w2    <none>           <none>

# BPF maps 조회
# 목적지 파드에 대한 tunnelendpoint. 즉 노드 IP가 있는것을 확인할 수 있다. 신기한 점은 동일한 노드의 경우에는 tunnelendpoint가 0.0.0.0이며, 노드에 대한 정보도 0.0.0.0이다. 
c2 map get cilium_ipcache
Key                 Value                                                                    State   Error
172.20.1.230/32     identity=6 encryptkey=0 tunnelendpoint=192.168.10.101 flags=<none>       sync
172.20.2.23/32      identity=21894 encryptkey=0 tunnelendpoint=192.168.10.100 flags=<none>   sync
172.20.2.242/32     identity=4 encryptkey=0 tunnelendpoint=192.168.10.100 flags=<none>       sync
0.0.0.0/0           identity=2 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.1.99/32      identity=19327 encryptkey=0 tunnelendpoint=192.168.10.101 flags=<none>   sync
172.20.0.21/32      identity=34931 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>          sync
172.20.0.200/32     identity=4 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.2.221/32     identity=6 encryptkey=0 tunnelendpoint=192.168.10.100 flags=<none>       sync
192.168.10.101/32   identity=6 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.0.156/32     identity=34931 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>          sync
10.0.2.15/32        identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.0.247/32     identity=19327 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>          sync
172.20.0.221/32     identity=7617 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>           sync
172.20.0.218/32     identity=7617 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>           sync
172.20.1.184/32     identity=4 encryptkey=0 tunnelendpoint=192.168.10.101 flags=<none>       sync
192.168.10.100/32   identity=7 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.0.92/32      identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
192.168.10.102/32   identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.0.213/32     identity=7617 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>           sync

# 목적지 파드에 대한 정보가 조회가 가능하다.
# c0 노드의 파드가 요청을 보낸다면 tunnelendpoint=192.168.10.102으로 패킷을 전달하게 된다.
c0 map get cilium_ipcache |grep 172.20.0.221
172.20.0.221/32     identity=7617 encryptkey=0 tunnelendpoint=192.168.10.102 flags=<none>    sync

# bpf 네트워크 인터페이스 조회 
# 여기서 lxc016a899bb2f4는 curl 파드이다.
c0bpf net show
xdp:
tc:
eth0(2) tcx/ingress cil_from_netdev prog_id 1975 link_id 16
eth0(2) tcx/egress cil_to_netdev prog_id 1973 link_id 17
eth1(3) tcx/ingress cil_from_netdev prog_id 1984 link_id 18
eth1(3) tcx/egress cil_to_netdev prog_id 1982 link_id 19
cilium_net(4) tcx/ingress cil_to_host prog_id 1963 link_id 15
cilium_host(5) tcx/ingress cil_to_host prog_id 1937 link_id 13
cilium_host(5) tcx/egress cil_from_host prog_id 1941 link_id 14
lxc_health(13) tcx/ingress cil_from_container prog_id 1929 link_id 28
lxc_health(13) tcx/egress cil_to_container prog_id 1916 link_id 29
lxc016a899bb2f4(15) tcx/ingress cil_from_container prog_id 1998 link_id 30
lxc016a899bb2f4(15) tcx/egress cil_to_container prog_id 2003 link_id 31

# curl 파드의 ingress에 대한 맵 정보는 prog_id 1998, exgress에 대한 정보는 2003인 것을 확인할 수 있다.
c0bpf net show | grep lxc016a899bb2f4
lxc016a899bb2f4(15) tcx/ingress cil_from_container prog_id 1998 link_id 30
lxc016a899bb2f4(15) tcx/egress cil_to_container prog_id 2003 link_id 31

# bpftool prog show는 프로세스에 대한 정보를 비롯하여 추가적인 ebpf 정보도 제공한다. 
# 이 중 map_ids인 312, 313, 35에 대해서 알아본다. 
c0bpf prog show id 1998
1998: sched_cls  name cil_from_container  tag 41989045bb171bee  gpl
	loaded_at 2025-07-19T16:42:31+0000  uid 0
	xlated 752B  jited 784B  memlock 4096B  map_ids 312,313,35
	btf_id 667

c0bpf prog show id 2003
2003: sched_cls  name cil_to_container  tag 0b3125767ba1861c  gpl
	loaded_at 2025-07-19T16:42:31+0000  uid 0
	xlated 1448B  jited 1144B  memlock 4096B  map_ids 312,35,313
	btf_id 672

c0bpf map list | grep -e 35: -e 312: -e 313: -A2
# CPU별 Cilium 성능 메트릭 수집
35: percpu_hash  name cilium_metrics  flags 0x1
	key 8B  value 16B  max_entries 1024  memlock 19024B
# 정적인 구성 값에 읽기 전용 MAP
312: array  name .rodata.config  flags 0x480
	key 4B  value 64B  max_entries 1  memlock 8192B
	btf_id 662  frozen
# 다른 BPF 프로그램과 연동하기 위한 prog_array
313: prog_array  name cilium_calls_00  flags 0x0
	key 4B  value 4B  max_entries 50  memlock 720B
	owner_prog_type sched_cls  owner jited
```

https://ebpf.io/ko-kr/what-is-ebpf/  
https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/    
https://cilium.isovalent.com/hubfs/marketing%20briefs/Isovalent%20-%20Cilium%20Cheat%20Sheet.pdf