## [Cilium Study 1기] 3주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 3주차 스터디에 대한 정리 글입니다. 

### IPAM
IPAM이란 cilium이 k8s 클러스터에서 파드 또는 서비스와 같은 IP를 필요로 하는 요소에 대해서 IP 관리 및 할당을 담당한다. IPAM 종류는 다양하며 각 IPAM마다 지원하는 기능이 다르므로 주의해서 구성해야 한다.

**IPAM 종류**
- k8s host(컨트롤러 매니저 관리)
- cluseter scope(default)
- Multi-Pool
- CRD-backed 
- AWS ENI  
- Azure IPAM
- GKE

https://docs.cilium.io/en/stable/network/concepts/ipam/

> 기존에 배포된 k8s의 IPAM은 변경해서는 안된다. 기존 워크로드의 중단이 야기될수 있다. IPAM을 변경하는 방법은 새 클러스터을 구축하는 것이다.

**k8s host scope**
```sh
# k8s 서비스 및 pod CIDR 조회
k cluster-info dump | grep -m 2 -E "cluster-cidr|service-cluster-ip-range"
    "--service-cluster-ip-range=10.96.0.0/16",
    "--cluster-cidr=10.244.0.0/16",

# ipam이 k8s scope이다
cilium config view | grep ^ipam
ipam                                              kubernetes

# 노드마다 다른 Pod CIDR 할당 조회
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
k8s-ctr	10.244.0.0/24
k8s-w1	10.244.1.0/24

# 컨트롤 매니저가 allocate-node-cidrs 옵션을 통해 노드별 파드 CIDR를 할당한다.
kc describe pod -n kube-system kube-controller-manager-k8s-ctr
Command:
    kube-controller-manager
    --allocate-node-cidrs=true
    --cluster-cidr=10.244.0.0/16
    --service-cluster-ip-range=10.96.0.0/16

# CiliumNode CRD를 통해 조회 시 ipam 옵션과 pod cidr 조회
k get ciliumnode -o json | grep ipam -A3
 "ipam": {
    "podCIDRs": [
        "10.244.0.0/24"
    ],
"ipam": {
    "podCIDRs": [
        "10.244.1.0/24"
    ],

k get ciliumendpoints.cilium.io -A
```

**샘플 애플리케이션 배포**
```sh
# k8s-ctr 노드에 curl-pod 파드 배포
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

# IP 확인
k get ciliumendpoints 
NAME                      SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
curl-pod                  12091               ready            10.244.0.22
webpod-697b545f57-f68x8   56171               ready            10.244.1.165
webpod-697b545f57-hzcjx   56171               ready            10.244.0.14

# curl과 web Pod간에 통신 확인
k exec -it curl-pod -- curl webpod | grep Hostname
k exec -it curl-pod -- sh -c 'while true; do curl -s webpod | grep Hostname; sleep 1; done'
```

**default scope**  
default scope는 k8s scope와 유사하다. 차이점은 k8s는 `v1.Node`가 관리하는 반면 default는 `v2.CiliumNode CRD`를 통해 관리한다. 이 모드의 장점은 k8s에 의존적이지 않다는 것이다. 최소 마스크 길이는 /30이며 권장 최소 마스크 길이는 /29 이상이다. 2개 주소는 예약됨(네트워크, 브로드캐스트 주소). default CIDR는 `10.0.0.0/8` 이다.

```sh
# IPAM을 default로 변경
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
--set ipam.mode="cluster-pool" \
--set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} \
--set ipv4NativeRoutingCIDR=172.20.0.0/16

# 오퍼레이터와 cilium 재시작 
k -n kube-system rollout restart deploy/cilium-operator
k -n kube-system rollout restart ds/cilium

# 노드의 Pod CIDR 조회한다. 하지만 기존 CIDR와 동일하다.
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
k8s-ctr	10.244.0.0/24
k8s-w1	10.244.1.0/24

# 하지만 cilium의 ipam은 k8s scope에서 cluster-pool로 변경되어있다.
cilium config view | grep ^ipam
ipam                                              cluster-pool
ipam-cilium-node-update-rate                      15s

# 앞서 k8s Node가 Pod CIDR를 관리한다 이야기한 것처럼, cilium도 ciliumNode CRD가 괸리한다.
# 하지만 PodCIDR는 기존과 동일하다.
k get ciliumnode -o json | grep podCIDRs -A2
                    "podCIDRs": [
                        "10.244.0.0/24"
--
                    "podCIDRs": [
                        "10.244.1.0/24"

# 모든 Pod의 IP도 변경사항이 없다. 
k get ciliumendpoints.cilium.io -A
NAMESPACE            NAME                                      SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
cilium-monitoring    grafana-5c69859d9-2brgn                   2036                ready            10.244.0.120
cilium-monitoring    prometheus-6fc896bc5d-rrlsv               17957               ready            10.244.0.220
default              curl-pod                                  12091               ready            10.244.0.22
default              webpod-697b545f57-f68x8                   56171               ready            10.244.1.165
default              webpod-697b545f57-hzcjx                   56171               ready            10.244.0.14
kube-system          coredns-674b8bbfcf-dvj2t                  6454                ready            10.244.0.2
kube-system          coredns-674b8bbfcf-k86l7                  6454                ready            10.244.0.35
kube-system          hubble-relay-5dcd46f5c-rtkkq              25617               ready            10.244.0.44
kube-system          hubble-ui-76d4965bb6-vshnf                5647                ready            10.244.0.145
local-path-storage   local-path-provisioner-74f9666bc9-5frvk   1188                ready            10.244.0.136

# ciliumnode가 이미 할당된 Pod CIDR를 초기화해주기 위해 ciliumnode 삭제 및 cilium을 재시작해줘야 한다.
k delete ciliumnode k8s-w1
k -n kube-system rollout restart ds/cilium

# 변경사항 확인. PodCIDR가 변경되었다.
k get ciliumnode -o json | grep podCIDRs -A2
                    "podCIDRs": [
                        "10.244.0.0/24"
                    ],
--
                    "podCIDRs": [
                        "172.20.0.0/24"
                    ],

# Pod CIDR도 기존과 동일하다.
k get ciliumendpoints.cilium.io -A
NAMESPACE            NAME                                      SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
cilium-monitoring    grafana-5c69859d9-2brgn                   2036                ready            10.244.0.120
cilium-monitoring    prometheus-6fc896bc5d-rrlsv               17957               ready            10.244.0.220
default              curl-pod                                  12091               ready            10.244.0.22
default              webpod-697b545f57-hzcjx                   56171               ready            10.244.0.14
kube-system          coredns-674b8bbfcf-dvj2t                  6454                ready            10.244.0.2
kube-system          coredns-674b8bbfcf-k86l7                  6454                ready            10.244.0.35
kube-system          hubble-relay-5dcd46f5c-rtkkq              25617               ready            10.244.0.44
kube-system          hubble-ui-76d4965bb6-vshnf                5647                ready            10.244.0.145
local-path-storage   local-path-provisioner-74f9666bc9-5frvk   1188                ready            10.244.0.136

# 마찬가지로 k8s-ctr 노드에도 동일한 작업 수행
k delete ciliumnode k8s-ctr
k -n kube-system rollout restart ds/cilium

# coredns의 ip가 자동 변경되었다
k get ciliumendpoints.cilium.io -A
NAMESPACE     NAME                       SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
kube-system   coredns-674b8bbfcf-mhmhf   6454                ready            172.20.0.253
kube-system   coredns-674b8bbfcf-rl6xg   6454                ready            172.20.1.112


ip -c route
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.0.0/16 via 192.168.10.200 dev eth1 proto static
172.20.0.0/24 via 192.168.10.101 dev eth1 proto kernel
172.20.1.112 dev lxce0180f9a7b33 proto kernel scope link
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.100

# node ip 확인 
k get ciliumnode -o wide
NAME      CILIUMINTERNALIP   INTERNALIP       AGE
k8s-ctr   172.20.1.138       192.168.10.100   3m5s
k8s-w1    172.20.0.11        192.168.10.101   6m25s

# pod의 ip는 동일하다.
k get pod -A -owide | grep 10.244.
cilium-monitoring    grafana-5c69859d9-2brgn                   0/1     Running            0             4d15h   10.244.0.120     k8s-ctr   <none>           <none>
cilium-monitoring    prometheus-6fc896bc5d-rrlsv               1/1     Running            0             4d15h   10.244.0.220     k8s-ctr   <none>           <none>
default              curl-pod                                  1/1     Running            0             4d12h   10.244.0.22      k8s-ctr   <none>           <none>
default              webpod-697b545f57-f68x8                   1/1     Running            0             4d12h   10.244.1.165     k8s-w1    <none>           <none>
default              webpod-697b545f57-hzcjx                   1/1     Running            0             4d12h   10.244.0.14      k8s-ctr   <none>           <none>
kube-system          hubble-relay-5dcd46f5c-rtkkq              0/1     Running            3 (13s ago)   4d15h   10.244.0.44      k8s-ctr   <none>           <none>
kube-system          hubble-ui-76d4965bb6-vshnf                1/2     CrashLoopBackOff   6 (16s ago)   4d15h   10.244.0.145     k8s-ctr   <none>           <none>
local-path-storage   local-path-provisioner-74f9666bc9-5frvk   1/1     Running            0             4d15h   10.244.0.136     k8s-ctr   <none>           <none>

# pod도 마찬가지로 재시작을 해줘야 한다. 
k -n kube-system rollout restart deploy/hubble-relay deploy/hubble-ui
k -n cilium-monitoring rollout restart deploy/prometheus deploy/grafana
k rollout restart deploy/webpod
k delete pod curl-pod

# ipam에 맞는 ip를 파드들이 할당받았다.
k get ciliumendpoints.cilium.io -A
NAMESPACE           NAME                           SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
cilium-monitoring   grafana-58b96b954-jqc8m        2036                ready            172.20.0.158
cilium-monitoring   prometheus-5494b8d8fc-c6xsf    17957               ready            172.20.0.150
default             curl-pod                       12091               ready            172.20.1.205
default             webpod-6dd689f7-g6qgx          56171               ready            172.20.0.111
default             webpod-6dd689f7-tsvpp          56171               ready            172.20.1.95
kube-system         coredns-674b8bbfcf-mhmhf       6454                ready            172.20.0.253
kube-system         coredns-674b8bbfcf-rl6xg       6454                ready            172.20.1.112
kube-system         hubble-relay-9d56b45cd-2ztnz   25617               ready            172.20.0.63
kube-system         hubble-ui-58c88f548f-877b6     5647                ready            172.20.0.12
```

정리하자면 ipam을 구성하기 위해서는 일련의 작업들이 필요하다
1. helm ipam을 `cluster scope`로 배포 
2. ciliumnode 삭제 
3. cilium 데몬셋 및 오퍼레이터 재시작. cilium 에이전트가 자동으로 ciliumnode을 생성하면서 pod cidr를 할당한다.
4. 기존 파드들 재시작

https://docs.cilium.io/en/stable/network/concepts/ipam/cluster-pool/


### Routing 
![](https://docs.cilium.io/en/stable/_images/native_routing.png)
 
cilium의 라우팅 종류 및 구성 옵션 
- Encapsulation(Vxlan, GENEVE)
  - tunnel-protocol: vxlan or geneve (default: vxlan)
  - tunnel-port
- native
  - routing-mode: native
  - ipv4-native-routing-cidr: x.x.x.x/y
  - auto-direct-node-routes: true

```sh
# 단축키(alias) 지정
export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
echo $CILIUMPOD0 $CILIUMPOD1 $CILIUMPOD2

alias c0="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium"
alias c1="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium"

# 웹 파드 ip 추출
k get pod -o wide
NAME                    READY   STATUS    RESTARTS   AGE     IP             NODE      NOMINATED NODE   READINESS GATES
curl-pod                1/1     Running   0          3m45s   172.20.1.205   k8s-ctr   <none>           <none>
webpod-6dd689f7-g6qgx   1/1     Running   0          4m22s   172.20.0.111   k8s-w1    <none>           <none>
webpod-6dd689f7-tsvpp   1/1     Running   0          3m46s   172.20.1.95    k8s-ctr   <none>           <none>

export WEBPODIP1=$(kubectl get -l app=webpod pods --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].status.podIP}')ㄴ
export WEBPODIP2=$(kubectl get -l app=webpod pods --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].status.podIP}')
echo $WEBPODIP1 $WEBPODIP2

# 통신 확인
k exec -it curl-pod -- ping $WEBPODIP2

# 즉 노드에서 pod CIDR를 알고 있고, 리눅스 라우팅 테이블로 pod의 ip에 바로 전달이 되는 것을 의미한다. 
# 172.20.0.0/24는 다른 노드의 cidr이다. 
ip -c route
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.0.0/16 via 192.168.10.200 dev eth1 proto static
172.20.0.0/24 via 192.168.10.101 dev eth1 proto kernel
172.20.1.95 dev lxc1f8b7b2e2d45 proto kernel scope link
172.20.1.112 dev lxce0180f9a7b33 proto kernel scope link
172.20.1.205 dev lxce6a3827bd387 proto kernel scope link
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.100

# hubble에서 pod간의 ip 과정 조회
cilium hubble port-forward&
hubble observe -f --pod curl-pod
Aug  2 05:34:45.973: default/curl-pod (ID:12091) -> default/webpod-6dd689f7-g6qgx (ID:56171) to-network FORWARDED (ICMPv4 EchoRequest)
Aug  2 05:34:45.973: default/curl-pod (ID:12091) -> default/webpod-6dd689f7-g6qgx (ID:56171) to-endpoint FORWARDED (ICMPv4 EchoRequest)

# 서로 다른 노드에 존재하는 파드임에도 직접 전달된다.
tcpdump -i eth1 icmp
14:35:45.364885 IP 172.20.1.205 > 172.20.0.111: ICMP echo request, id 37, seq 123, length 64
14:35:45.365207 IP 172.20.0.111 > 172.20.1.205: ICMP echo reply, id 37, seq 123, length 64

# tcpdump 패킷 저장 후 터미널 형태의 와어이샤크로 패킷을 조회한디
tcpdump -i eth1 icmp -w /tmp/icmp.pcap
termshark -r /tmp/icmp.pcap
```

https://docs.cilium.io/en/stable/network/concepts/routing/


### Masquerading
![](https://docs.cilium.io/en/stable/_images/masquerade.png)

Masquerading 구현 방식 
- eBPF-based 
- iptables-based

주요 옵션
- ipv4-native-routing-cidr: 10.0.0/8 
- bpf.masquerade=true
- ipMasqAgent.enabled=true
- ipMasqAgent.config.nonMasqueradeCIDRs='{10.10.1.0/24,10.10.2.0/24}'

```sh
# cilium Masquerading 설정 조회
k exec -it -n kube-system ds/cilium -c cilium-agent  -- cilium status | grep Masquerading
Masquerading:            BPF   [eth0, eth1]   172.20.0.0/16 [IPv4: Enabled, IPv6: Disabled]

# Masquerading을 수행하지 않는 cidr 조회 
cilium config view  | grep ipv4-native-routing-cidr
ipv4-native-routing-cidr                          172.20.0.0/16

# k8s-ctr. 2개의 터미널로 조회
# pod의 ip가 그대로 찍힌다.
tcpdump -i eth1 icmp -nn
k exec -it curl-pod -- ping 192.168.10.101
14:39:12.170590 IP 172.20.1.205 > 192.168.10.101: ICMP echo request, id 42, seq 1, length 64
14:39:12.171041 IP 192.168.10.101 > 172.20.1.205: ICMP echo reply, id 42, seq 1, length 64

# router
ip -br -c -4 addr
lo               UNKNOWN        127.0.0.1/8
eth0             UP             10.0.2.15/24 metric 100
eth1             UP             192.168.10.200/24
loop1            UNKNOWN        10.10.1.200/24
loop2            UNKNOWN        10.10.2.200/24

# k8s-ctr
# static route 조회
ip -c route | grep static
10.10.0.0/16 via 192.168.10.200 dev eth1 proto static

# k8s-ctr 
tcpdump -i eth1 tcp port 80 -nnq
# router 
tcpdump -i eth1 tcp port 80 -nnq

# curl 수행 
k exec -it curl-pod -- curl -s 10.10.1.200
k exec -it curl-pod -- curl -s 10.10.2.200

# tcpdump 결과
14:50:00.788456 IP 10.10.2.200.80 > 192.168.10.100.57882: tcp 0
14:50:00.788561 IP 192.168.10.100.57882 > 10.10.2.200.80: tcp 0
14:50:00.788612 IP 192.168.10.100.57882 > 10.10.2.200.80: tcp 75
14:50:00.788841 IP 10.10.2.200.80 > 192.168.10.100.57882: tcp 0
14:50:00.789506 IP 10.10.2.200.80 > 192.168.10.100.57882: tcp 256
14:50:00.789551 IP 192.168.10.100.57882 > 10.10.2.200.80: tcp 0
14:50:00.789756 IP 192.168.10.100.57882 > 10.10.2.200.80: tcp 0
14:50:00.789992 IP 10.10.2.200.80 > 192.168.10.100.57882: tcp 0
14:50:00.790070 IP 192.168.10.100.57882 > 10.10.2.200.80: tcp 0
```

`nonMasqueradeCIDRs`을 통해 Masquerading 하지 않는 네트워크를 설정할수 있다. 설정 값이 없는 경우 하단의 설정이 적용되며, 하단의 IP에 대해서는 Masquerading하지 않는다. 사실상 대부분의 사설 IP 대역대라고 봐도 무방하다.

```
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
100.64.0.0/10
192.0.0.0/24
192.0.2.0/24
192.88.99.0/24
198.18.0.0/15
198.51.100.0/24
203.0.113.0/24
240.0.0.0/4
```


```sh
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set ipMasqAgent.enabled=true \
  --set ipMasqAgent.config.nonMasqueradeCIDRs='{10.10.1.0/24,10.10.2.0/24}'

# ip-masq-agent 설정 조회 
k get cm -n kube-system ip-masq-agent -o yaml | yq
{
  "apiVersion": "v1",
  "data": {
    "config": "{\"nonMasqueradeCIDRs\":[\"10.10.1.0/24\",\"10.10.2.0/24\"]}"
  },
  "kind": "ConfigMap",
  "metadata": {
    "annotations": {
      "meta.helm.sh/release-name": "cilium",
      "meta.helm.sh/release-namespace": "kube-system"
    },
    "creationTimestamp": "2025-08-02T05:56:20Z",
    "labels": {
      "app.kubernetes.io/managed-by": "Helm"
    },
    "name": "ip-masq-agent",
    "namespace": "kube-system",
    "resourceVersion": "30748",
    "uid": "d9bbb69d-4366-4fa4-91f7-83edad056c09"
  }
}

cilium config view  | grep -i ip-masq
enable-ip-masq-agent                              true

# nonMasqueradeCIDRs bpf 조회 
# masqLinkLocal가 설정되어 있지 않아 169.254.0.0/16가 자동으로 추가되어 있다.
k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf ipmasq list
IP PREFIX/ADDRESS
169.254.0.0/16
10.10.1.0/24
10.10.2.0/24

# 터미널 2개 사용
# k8s-ctr
tcpdump -i eth1 tcp port 80 -nnq 혹은 hubble observe -f --pod curl-pod
# router
tcpdump -i eth1 tcp port 80 -nnq

# curl 수행
kubectl exec -it curl-pod -- curl -s 10.10.1.200
kubectl exec -it curl-pod -- curl -s 10.10.2.200

# 파드의 ip, snat처리 되지 않고 유지된다. 
14:58:55.765539 IP 172.20.1.205.46052 > 10.10.1.200.80: tcp 0
14:58:54.766152 IP 172.20.1.205.46052 > 10.10.1.200.80: tcp 0

kubectl get ciliumnode -o json |grep -i podcidr -A2
                    "podCIDRs": [
                        "172.20.1.0/24"
                    ],
--
                    "podCIDRs": [
                        "172.20.0.0/24"
                    ],


# router 노드에서 정적으로 route 추가해준다. 
ip route add 172.20.1.0/24 via 192.168.10.100
ip route add 172.20.0.0/24 via 192.168.10.101

# 라우팅 테이블 조회
ip -c route | grep 172.20
172.20.0.0/24 via 192.168.10.101 dev eth1
172.20.1.0/24 via 192.168.10.100 dev eth1

k exec -it curl-pod -- curl -s 10.10.1.200

# 통신 확인 
tcpdump -i eth1 tcp port 80 -nnq
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
15:01:53.407939 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 0
15:01:53.408287 IP 10.10.1.200.80 > 172.20.1.205.49872: tcp 0
15:01:53.408374 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 0
15:01:53.408479 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 75
15:01:53.408695 IP 10.10.1.200.80 > 172.20.1.205.49872: tcp 0
15:01:53.409878 IP 10.10.1.200.80 > 172.20.1.205.49872: tcp 256
15:01:53.409924 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 0
15:01:53.410112 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 0
15:01:53.410335 IP 10.10.1.200.80 > 172.20.1.205.49872: tcp 0
15:01:53.410397 IP 172.20.1.205.49872 > 10.10.1.200.80: tcp 0
```

https://docs.cilium.io/en/stable/network/concepts/masquerading/


### CoreDNS
```sh
# 파드 내의 resolve.conf가 존재한다. coredns 덕에 서비스를 서비스를 dns형태로 조회가 가능하다.
k exec -it curl-pod -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

# kubelet 설정에 coredns의 서비스 ip와 도메인이 정의되어 있다.
cat /var/lib/kubelet/config.yaml | grep cluster -A1
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
containerRuntimeEndpoint: ""

# kube-dns 서비스 조회
# 앞선 설정과 동일한 ip를 가지고 있다. 
k get svc,ep -n kube-system kube-dns
NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
service/kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   4d15h
NAME                 ENDPOINTS                                                     AGE
endpoints/kube-dns   172.20.0.253:53,172.20.1.112:53,172.20.0.253:53 + 3 more...   4d15h

k get pod -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS   AGE
coredns-674b8bbfcf-mhmhf   1/1     Running   0          40m
coredns-674b8bbfcf-rl6xg   1/1     Running   0          39m

# coredns는 어떻게 구성이 되어있을까?
# cm을 통해서 설정이 구성되어 있다. 
kc describe pod -n kube-system -l k8s-app=kube-dns | grep -i volumes -A5
Volumes:
  config-volume:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      coredns

# k8s내에서 서비스를 전달 방법과 서비스가 없는 경우 노드의 resolve.conf을 읽어 처리한다.
kc describe cm -n kube-system coredns
Name:         coredns
Namespace:    kube-system
Data
====
Corefile:
----
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload # 설정 변경시 자동 재적용. 적용 시간 최대 2분 소요
    loadbalance
}

# 노드의 설정 조회
cat /etc/resolv.conf
nameserver 127.0.0.53
options edns0 trust-ad
search .

resolvectl
Global
  Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
  resolv.conf mode: stub
Link 2 (eth0)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 10.0.2.3
       DNS Servers: 10.0.2.3

# dns 패킷 흐름 조회
cilium hubble port-forward&
hubble observe -f --port 53 --protocol UDP

# coredns 감소 
k scale deployment -n kube-system coredns --replicas 1
# 메트릭 조회 
k exec -it curl-pod -- curl kube-dns.kube-system.svc:9153/metrics | grep coredns_cache_ | grep -v ^#
coredns_cache_entries{server="dns://:53",type="denial",view="",zones="."} 1
coredns_cache_entries{server="dns://:53",type="success",view="",zones="."} 0
coredns_cache_misses_total{server="dns://:53",view="",zones="."} 17
coredns_cache_requests_total{server="dns://:53",view="",zones="."} 17

# curl-pod에서 요청 수행 시 다음과 같은 흐름으로 동작한다.
Aug  2 06:07:50.429: default/curl-pod (ID:12091) <> 10.96.0.10:53 (world) pre-xlate-fwd TRACED (UDP)
Aug  2 06:07:50.429: default/curl-pod (ID:12091) <> kube-system/coredns-674b8bbfcf-rl6xg:53 (ID:6454) post-xlate-fwd TRANSLATED (UDP)
Aug  2 06:07:50.430: default/curl-pod:47603 (ID:12091) -> kube-system/coredns-674b8bbfcf-rl6xg:53 (ID:6454) to-endpoint FORWARDED (UDP)
Aug  2 06:07:50.431: kube-system/coredns-674b8bbfcf-rl6xg:53 (ID:6454) <> default/curl-pod (ID:12091) pre-xlate-rev TRACED (UDP)
Aug  2 06:07:50.431: 10.96.0.10:53 (world) <> default/curl-pod (ID:12091) post-xlate-rev TRANSLATED (UDP)

k exec -it curl-pod -- nslookup -debug webpod
;; Got recursion not available from 10.96.0.10
Server:		10.96.0.10
Address:	10.96.0.10#53
------------
  QUESTIONS:
webpod.default.svc.cluster.local, type = A, class = IN
  ANSWERS:
  ->  webpod.default.svc.cluster.local
internet address = 10.96.173.243
ttl = 30
  AUTHORITY RECORDS:
  ADDITIONAL RECORDS:
------------
Name:	webpod.default.svc.cluster.local
Address: 10.96.173.243
;; Got recursion not available from 10.96.0.10
------------
  QUESTIONS:
webpod.default.svc.cluster.local, type = AAAA, class = IN
  ANSWERS:
  AUTHORITY RECORDS:
  ->  cluster.local
origin = ns.dns.cluster.local
mail addr = hostmaster.cluster.local
serial = 1754114852
refresh = 7200
retry = 1800
expire = 86400
minimum = 30
ttl = 30
  ADDITIONAL RECORDS:
------------
```

https://coredns.io/manual/toc/  
https://coredns.io/plugins/


### NodeLocalDNS 
![](https://kubernetes.io/images/docs/nodelocaldns.svg)

목표 
- 노드에 coredns가 없는 경우, 로컬 캐시를 통한 지연 시간 감소 
- iptables DNAT 및 연결 추적을 건너 뛰어 conntrack 테이블 항목 감소
- 노드 수준에서 DNS 요청에 대한 메트릭 및 가시성 확보 
- kub-dns에 대한 쿼리 수 감소 
- DNS 쿼리를 UDP에서 TCP로 업그레이드하면 삭제된 UDP 패킷으로 인한 테일 대기 시간 및 DNS 시간 초과가 일반적으로 최대 30초(3회 재시도 + 10초 시간 초과)로 줄어듭니다. nodelocal 캐시는 UDP DNS 쿼리를 수신 대기하므로 애플리케이션을 변경할 필요가 없습니다
- 로컬 캐싱 에이전트에서 kube-dns 서비스로의 연결은 TCP로 업그레이드할 수 있다. TCP conntrack 항목은 시간 초과가 필요한 UDP 항목과 달리 연결 종료 시 제거됩니다(기본값 nf_conntrack_udp_timeout는 30초)

```sh
wget https://github.com/kubernetes/kubernetes/raw/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

kubedns=`kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}`
domain='cluster.local'    
localdns='169.254.20.10'  
echo $kubedns $domain $localdns

# iptables를 사용하는 경우 다음 명령어 수행 
sed -i "s/__PILLAR__LOCAL__DNS__/$localdns/g; s/__PILLAR__DNS__DOMAIN__/$domain/g; s/__PILLAR__DNS__SERVER__/$kubedns/g" nodelocaldns.yaml

k apply -f nodelocaldns.yaml

k get pod -n kube-system -l k8s-app=node-local-dns -o wide
NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE      NOMINATED NODE   READINESS GATES
node-local-dns-6dhnl   1/1     Running   0          66s   10.10.0.50   k8s-ctr   <none>           <none>
node-local-dns-p4c2m   1/1     Running   0          64s   10.10.0.16   k8s-w1    <none>           <none>

# log, debug 추가
k edit cm -n kube-system node-local-dns 
k -n kube-system rollout restart ds node-local-dns

# node-local-nds 설정 조회
k describe cm -n kube-system node-local-dns
Name:         node-local-dns
Namespace:    kube-system
Data
====
Corefile:
----
cluster.local:53 {
    log # 추가된 항목
    debug # 추가된 항목 
    errors
    cache {
            success 9984 30
            denial 9984 5
    }
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . __PILLAR__CLUSTER__DNS__ {
            force_tcp
    }
    prometheus :9253
    health 169.254.20.10:8080
    }
in-addr.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . __PILLAR__CLUSTER__DNS__ {
            force_tcp
    }
    prometheus :9253
    }

iptables -t filter -S | grep -i dns
-A INPUT -d 10.96.0.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A INPUT -d 10.96.0.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A INPUT -d 169.254.20.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A INPUT -d 169.254.20.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A OUTPUT -s 10.96.0.10/32 -p udp -m udp --sport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A OUTPUT -s 10.96.0.10/32 -p tcp -m tcp --sport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A OUTPUT -s 169.254.20.10/32 -p udp -m udp --sport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT
-A OUTPUT -s 169.254.20.10/32 -p tcp -m tcp --sport 53 -m comment --comment "NodeLocal DNS Cache: allow DNS traffic" -j ACCEPT

iptables -t raw -S | grep -i dns
-A PREROUTING -d 10.96.0.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A PREROUTING -d 10.96.0.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A PREROUTING -d 169.254.20.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A PREROUTING -d 169.254.20.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 10.96.0.10/32 -p tcp -m tcp --sport 8080 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 10.96.0.10/32 -p tcp -m tcp --dport 8080 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 10.96.0.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 10.96.0.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 10.96.0.10/32 -p udp -m udp --sport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 10.96.0.10/32 -p tcp -m tcp --sport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 169.254.20.10/32 -p tcp -m tcp --sport 8080 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 169.254.20.10/32 -p tcp -m tcp --dport 8080 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 169.254.20.10/32 -p udp -m udp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -d 169.254.20.10/32 -p tcp -m tcp --dport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 169.254.20.10/32 -p udp -m udp --sport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK
-A OUTPUT -s 169.254.20.10/32 -p tcp -m tcp --sport 53 -m comment --comment "NodeLocal DNS Cache: skip conntrack" -j NOTRACK

k exec -it curl-pod -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

k exec -it curl-pod -- nslookup webpod
;; Got recursion not available from 10.96.0.10
Server:		10.96.0.10
Address:	10.96.0.10#53
Name:	webpod.default.svc.cluster.local
Address: 10.96.173.243
;; Got recursion not available from 10.96.0.10

k exec -it curl-pod -- nslookup google.com
;; Got recursion not available from 10.96.0.10
Server:		10.96.0.10
Address:	10.96.0.10#53
Non-authoritative answer:
Name:	google.com
Address: 172.217.31.142
Name:	google.com
Address: 2404:6800:4004:808::200e

k delete pod curl-pod

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  labels:
    app: curl
spec:
  containers:
  - name: curl
    image: nicolaka/netshoot
    command: ["tail"]
    args: ["-f", "/dev/null"]
  terminationGracePeriodSeconds: 0
EOF

k exec -it curl-pod -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

k exec -it curl-pod -- nslookup google.com
;; Got recursion not available from 10.96.0.10
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	google.com
Address: 172.217.31.142
Name:	google.com
Address: 2404:6800:4004:808::200e

# LRP 활성화
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set localRedirectPolicy=true

k rollout restart deploy cilium-operator -n kube-system
k rollout restart ds cilium -n kube-system

wget https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/kubernetes-local-redirect/node-local-dns.yaml

kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP})
sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml

vi -d nodelocaldns.yaml node-local-dns.yaml
## before
args: [ "-localip", "169.254.20.10,10.96.0.10", "-conf", "/etc/Corefile", "-upstreamsvc", "kube-dns-upstream" ]
## after
args: [ "-localip", "169.254.20.10,10.96.0.10", "-conf", "/etc/Corefile", "-upstreamsvc", "kube-dns-upstream", "-skipteardown=true", "-setupinterface=false", "-setupiptables=false" ]

k apply -f node-local-dns.yaml

# 설정에서 log, debug 항목 추가 
k edit cm -n kube-system node-local-dns

k describe cm -n kube-system node-local-dns
Name:         node-local-dns
Namespace:    kube-system
Labels:       <none>
Annotations:  <none>

Data
====
Corefile:
----
cluster.local:53 {
    debug # 추가 항목 
    log # 추가 항목 
    errors
    cache {
            success 9984 30
            denial 9984 5
    }
    reload
    loop
    bind 0.0.0.0
    forward . __PILLAR__CLUSTER__DNS__ {
            force_tcp
    }
    prometheus :9253
    health
    }
in-addr.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 0.0.0.0
    forward . __PILLAR__CLUSTER__DNS__ {
            force_tcp
    }
    prometheus :9253
    }
ip6.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 0.0.0.0
    forward . __PILLAR__CLUSTER__DNS__ {
            force_tcp
    }
    prometheus :9253
    }
.:53 {
    errors
    cache 30
    reload
    loop
    bind 0.0.0.0
    forward . __PILLAR__UPSTREAM__SERVERS__
    prometheus :9253
    }

# cilium에서 nodeclocaldns가 동작하기 위해서는 하단의 과정이 수행되어야 한다
# pod의 veth 인터페이스 또는 그 이전에 서비스 확인을 처리할 때 우회하여 처리되기 때문이다
wget https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/kubernetes-local-redirect/node-local-dns-lrp.yaml
cat node-local-dns-lrp.yaml | yq
{
  "apiVersion": "cilium.io/v2",
  "kind": "CiliumLocalRedirectPolicy",
  "metadata": {
    "name": "nodelocaldns",
    "namespace": "kube-system"
  },
  "spec": {
    "redirectFrontend": {
      "serviceMatcher": {
        "serviceName": "kube-dns",
        "namespace": "kube-system"
      }
    },
    "redirectBackend": {
      "localEndpointSelector": {
        "matchLabels": {
          "k8s-app": "node-local-dns"
        }
      },
      "toPorts": [
        {
          "port": "53",
          "name": "dns",
          "protocol": "UDP"
        },
        {
          "port": "53",
          "name": "dns-tcp",
          "protocol": "TCP"
        }
      ]
    }
  }
}

k apply -f node-local-dns-lrp.yaml

# LRP 조회 
# 동일한 네임스페이스에 생성되어야 한다. 
k get CiliumLocalRedirectPolicy -n kube-system 
NAMESPACE     NAME           AGE
kube-system   nodelocaldns   6s

# 로컬 pod 조회
k exec -it -n kube-system ds/cilium -c cilium-agent -- cilium-dbg lrp list
LRP namespace   LRP name       FrontendType                Matching Service
kube-system     nodelocaldns   clusterIP + all svc ports   kube-system/kube-dns
                |              10.96.0.10:53/UDP -> 172.20.1.236:53(kube-system/node-local-dns-nnt9r),
                |              10.96.0.10:53/TCP -> 172.20.1.236:53(kube-system/node-local-dns-nnt9r),
                |              10.96.0.10:9153/TCP ->
k exec -it -n kube-system ds/cilium -c cilium-agent -- cilium-dbg service list | grep LocalRedirect
16   10.96.0.10:53/UDP          LocalRedirect   1 => 172.20.1.236:53/UDP (active)
17   10.96.0.10:53/TCP          LocalRedirect   1 => 172.20.1.236:53/TCP (active)

# 서로 다른 터미널을 띄운 후에 로그를 출력하면 lrp로 nodelocaldns로 요청이 가는 것을 확인할 수가 있다.
k -n kube-system logs -l k8s-app=kube-dns -f
k -n kube-system logs -l k8s-app=node-local-dns -f

k exec -it curl-pod -- nslookup www.google.com
[INFO] 127.0.0.1:34719 - 51270 "HINFO IN 7934366777012586703.5963991577258739271.cluster.local. udp 71 false 512" NXDOMAIN qr,aa,rd 164 0.0029825s
[INFO] 172.20.1.72:38808 - 10243 "A IN www.google.com.default.svc.cluster.local. udp 58 false 512" NXDOMAIN qr,aa,rd 151 0.001189416s
[INFO] 172.20.1.72:41993 - 47288 "A IN www.google.com.svc.cluster.local. udp 50 false 512" NXDOMAIN qr,aa,rd 143 0.000486792s
[INFO] 172.20.1.72:58050 - 6898 "A IN www.google.com.cluster.local. udp 46 false 512" NXDOMAIN qr,aa,rd 139 0.0004105s
```

https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/    
https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/#configuration    
https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache