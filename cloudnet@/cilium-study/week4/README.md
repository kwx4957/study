## [Cilium Study 1기] 4주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 4주차 스터디에 대한 정리 글입니다. 

### 샘플 애플리케이션 배포
```sh
cat << EOF | kubectl apply -f -
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
```

### 현재 진행도 확인
```sh
k get ciliumendpoints
NAME                            SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
curl-pod                        2163                ready            172.20.0.102
netshoot-web-5c59d94bd4-clw2v   55713               ready            172.20.2.230
netshoot-web-5c59d94bd4-j5hzw   55713               ready            172.20.0.36
netshoot-web-5c59d94bd4-k7bjk   55713               ready            172.20.1.117
webpod-697b545f57-2nk8p         2219                ready            172.20.2.77
webpod-697b545f57-kf46p         2219                ready            172.20.1.219
webpod-697b545f57-rpxqc         2219                ready            172.20.0.158

k exec -it -n kube-system ds/cilium -- cilium-dbg ip list
k exec -n kube-system ds/cilium -- cilium-dbg endpoint list
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                              IPv6   IPv4           STATUS
           ENFORCEMENT        ENFORCEMENT
200        Disabled           Disabled          2219       k8s:app=webpod                                                                  172.20.1.219   ready
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
234        Disabled           Disabled          1          reserved:host                                                                                  ready
3691       Disabled           Disabled          55713      k8s:app=netshoot-web                                                            172.20.1.117   ready
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default

k exec -n kube-system ds/cilium -- cilium-dbg service list
ID   Frontend                Service Type   Backend
1    0.0.0.0:30003/TCP       NodePort       1 => 172.20.0.11:8081/TCP (active)
4    10.96.155.166:80/TCP    ClusterIP      1 => 172.20.0.11:8081/TCP (active)
5    0.0.0.0:30002/TCP       NodePort       1 => 172.20.0.1:3000/TCP (active)
8    10.96.109.67:3000/TCP   ClusterIP      1 => 172.20.0.1:3000/TCP (active)
9    0.0.0.0:30001/TCP       NodePort       1 => 172.20.0.240:9090/TCP (active)
12   10.96.146.52:9090/TCP   ClusterIP      1 => 172.20.0.240:9090/TCP (active)
13   10.96.0.1:443/TCP       ClusterIP      1 => 192.168.10.100:6443/TCP (active)
14   10.96.217.172:443/TCP   ClusterIP      1 => 192.168.10.101:4244/TCP (active)
15   10.96.38.34:80/TCP      ClusterIP      1 => 172.20.0.254:4245/TCP (active)
16   10.96.0.10:53/TCP       ClusterIP      1 => 172.20.0.56:53/TCP (active)
                                            2 => 172.20.0.244:53/TCP (active)
17   10.96.0.10:53/UDP       ClusterIP      1 => 172.20.0.56:53/UDP (active)
                                            2 => 172.20.0.244:53/UDP (active)
18   10.96.0.10:9153/TCP     ClusterIP      1 => 172.20.0.56:9153/TCP (active)
                                            2 => 172.20.0.244:9153/TCP (active)
19   10.96.218.119:443/TCP   ClusterIP      1 => 172.20.0.139:10250/TCP (active)
20   10.96.48.145:80/TCP     ClusterIP      1 => 172.20.0.158:80/TCP (active)
                                            2 => 172.20.1.219:80/TCP (active)
                                            3 => 172.20.2.77:80/TCP (active)
21   0.0.0.0:32050/TCP       NodePort       1 => 172.20.0.158:80/TCP (active)
                                            2 => 172.20.1.219:80/TCP (active)
                                            3 => 172.20.2.77:80/TCP (active)
24   192.168.10.211:80/TCP   LoadBalancer   1 => 172.20.0.158:80/TCP (active)
                                            2 => 172.20.1.219:80/TCP (active)
                                            3 => 172.20.2.77:80/TCP (active)
25   0.0.0.0:30412/TCP       NodePort       1 => 172.20.0.36:8080/TCP (active)
                                            2 => 172.20.1.117:8080/TCP (active)
                                            3 => 172.20.2.230:8080/TCP (active)
28   10.96.56.141:80/TCP     ClusterIP      1 => 172.20.0.36:8080/TCP (active)
                                            2 => 172.20.1.117:8080/TCP (active)
                                            3 => 172.20.2.230:8080/TCP (active)
29   192.168.10.212:80/TCP   LoadBalancer   1 => 172.20.0.36:8080/TCP (active)
                                            2 => 172.20.1.117:8080/TCP (active)
                                            3 => 172.20.2.230:8080/TCP (active)

k exec -n kube-system ds/cilium -- cilium-dbg bpf lb list

# webpod의 서비스 주소로 조회
k exec -n kube-system ds/cilium -- cilium-dbg bpf lb list | grep 10.96.48.145
10.96.48.145:80/TCP (2)        172.20.1.219:80/TCP (20) (2)
10.96.48.145:80/TCP (3)        172.20.2.77:80/TCP (20) (3)
10.96.48.145:80/TCP (1)        172.20.0.158:80/TCP (20) (1)
10.96.48.145:80/TCP (0)        0.0.0.0:0 (20) (0) [ClusterIP, non-routable]


k exec -n kube-system ds/cilium -- cilium-dbg bpf nat list

k exec -n kube-system ds/cilium -- cilium-dbg map list | grep -v '0             0'
Name                           Num entries   Num errors   Cache enabled
cilium_runtime_config          256           0            true
cilium_lb4_services_v2         81            0            true
cilium_lb4_backends_v3         19            0            true
cilium_ipcache_v2              25            0            true
cilium_policy_v2_00200         3             0            true
cilium_policy_v2_00234         2             0            true
cilium_policy_v2_03691         3             0            true
cilium_lb4_reverse_nat         29            0            true
cilium_lxc                     2             0            true

k exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_services_v2 | grep 10.96.48.145
10.96.48.145:80/TCP (0)        0 3[0] (20) [0x0 0x0]
10.96.48.145:80/TCP (1)        23 0[0] (20) [0x0 0x0]
10.96.48.145:80/TCP (3)        16 0[0] (20) [0x0 0x0]
10.96.48.145:80/TCP (2)        15 0[0] (20) [0x0 0x0]

k exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_backends_v3
Key   Value                  State   Error
33    TCP://172.20.0.139
29    UDP://172.20.0.244
37    TCP://172.20.1.117
36    TCP://172.20.2.230
27    TCP://172.20.0.244
35    TCP://172.20.0.36
25    TCP://172.20.0.11
31    TCP://172.20.0.244
24    TCP://172.20.0.240
30    TCP://172.20.0.56
26    TCP://172.20.0.56
32    TCP://172.20.0.1
21    TCP://192.168.10.101
34    TCP://172.20.0.254
4     TCP://192.168.10.100
16    TCP://172.20.2.77
23    TCP://172.20.0.158
15    TCP://172.20.1.219
28    UDP://172.20.0.56

k exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_reverse_nat
Key   Value                  State   Error
4     10.96.155.166:80
8     10.96.109.67:3000
13    10.96.0.1:443
21    0.0.0.0:32050
1     0.0.0.0:30003
9     0.0.0.0:30001
22    10.0.2.15:32050
15    10.96.38.34:80
25    0.0.0.0:30412
19    10.96.218.119:443
7     192.168.10.101:30002
28    10.96.56.141:80
10    10.0.2.15:30001
2     10.0.2.15:30003
29    192.168.10.212:80
3     192.168.10.101:30003
18    10.96.0.10:9153
27    192.168.10.101:30412
24    192.168.10.211:80
17    10.96.0.10:53
26    10.0.2.15:30412
5     0.0.0.0:30002
12    10.96.146.52:9090
6     10.0.2.15:30002
16    10.96.0.10:53
23    192.168.10.101:32050
14    10.96.217.172:443
11    192.168.10.101:30001
20    10.96.48.145:80

k exec -n kube-system ds/cilium -- cilium-dbg map get cilium_ipcache_v2
Key                 Value                                                                       State   Error
172.20.0.11/32      identity=472 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel     sync
172.20.0.0/24       identity=2 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel       sync
172.20.1.141/32     identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
172.20.2.160/32     identity=6 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel       sync
172.20.2.0/24       identity=2 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel       sync
172.20.0.244/32     identity=6959 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
172.20.0.240/32     identity=59394 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel   sync
172.20.0.158/32     identity=2219 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
172.20.1.219/32     identity=2219 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>              sync
172.20.0.139/32     identity=38507 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel   sync
172.20.2.230/32     identity=55713 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel   sync
192.168.10.101/32   identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
0.0.0.0/0           identity=2 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
172.20.0.36/32      identity=55713 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel   sync
172.20.0.254/32     identity=36329 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel   sync
172.20.2.77/32      identity=2219 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel    sync
172.20.0.1/32       identity=2246 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
172.20.0.56/32      identity=6959 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
192.168.20.100/32   identity=6 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
192.168.10.100/32   identity=7 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
10.0.2.15/32        identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>                 sync
172.20.0.102/32     identity=2163 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
172.20.1.117/32     identity=55713 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>             sync
172.20.0.192/32     identity=6 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel       sync
172.20.0.108/32     identity=7135 encryptkey=0 tunnelendpoint=192.168.10.100 flags=hastunnel    sync
```

### 통신 오류 해결하기
```sh
# 통신 확인. 그러나 통신이 안됌
k exec -it curl-pod -- curl webpod | grep Hostname

k get pods -o wide | grep webpod
NAME                      READY   STATUS    RESTARTS   AGE
webpod-697b545f57-2nk8p   1/1     Running   0          3m47s   172.20.2.77    k8s-w0    <none>           <none>
webpod-697b545f57-kf46p   1/1     Running   0          3m47s   172.20.1.219   k8s-w1    <none>           <none>
webpod-697b545f57-rpxqc   1/1     Running   0          3m47s   172.20.0.126   k8s-ctr   <none>           <none>

# 3개의 파드 중 2개의 파드만 응답한다. 2nk8p 파드는 응답하지 않는다. 즉 k8s-w0 노드와는 통신이 안된다고 볼 수 있다.
k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'
Hostname: webpod-697b545f57-kf46p
---
Hostname: webpod-697b545f57-rpxqc
---

# 통신이 안되는 파드 IP 추출
export WEBPOD=$(kubectl get pod -l app=webpod --field-selector spec.nodeName=k8s-w0 -o jsonpath='{.items[0].status.podIP}')
echo $WEBPOD

# Router 서버
tcpdump -i any icmp -nn

# curl Pod -> 통신 안되는 파드 ICMP 전송 
k exec -it curl-pod -- ping -c 2 -w 1 -W 1 $WEBPOD
1 packets transmitted, 0 received, 100% packet loss, time 0ms

# tcp 결과 
# eth1(192.168.10.200)으로 요청이 들어와서 eth0(10.0.2.15/24)으로 나가려한다.
14:11:26.936964 eth1  In  IP 172.20.0.53 > 172.20.2.77: ICMP echo request, id 119, seq 1, length 64
14:11:26.936980 eth0  Out IP 172.20.0.53 > 172.20.2.77: ICMP echo request, id 119, seq 1, length 64

# 왜냐하면 172.20.2.0/24에 해당하는 조건이 없기 때문에 기본 라우트 설정인 eth0으로 패킷이 빠지게 된다. 
ip -c route
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.1.0/24 dev loop1 proto kernel scope link src 10.10.1.200
10.10.2.0/24 dev loop2 proto kernel scope link src 10.10.2.200
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.200
192.168.20.0/24 dev eth2 proto kernel scope link src 192.168.20.200

# 해당 IP가 나가는 라우트 정보 조회
ip route get 172.20.2.77
172.20.2.77 via 10.0.2.2 dev eth0 src 10.0.2.15 uid 0
    cache

# Router
tcpdump -i any tcp port 80 -nn
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
14:17:59.436155 eth1  In  IP 172.20.0.53.34980 > 172.20.2.77.80: Flags [S], seq 101042966, win 64240, options [mss 1460,sackOK,TS val 1430010626 ecr 0,nop,wscale 7], length 0
14:17:59.436164 eth0  Out IP 172.20.0.53.34980 > 172.20.2.77.80: Flags [S], seq 101042966, win 64240, options [mss 1460,sackOK,TS val 1430010626 ecr 0,nop,wscale 7], length 0
14:18:00.436675 eth1  In  IP 172.20.0.53.34980 > 172.20.2.77.80: Flags [S], seq 101042966, win 64240, options [mss 1460,sackOK,TS val 1430011627 ecr 0,nop,wscale 7], length 0
14:18:00.436681 eth0  Out IP 172.20.0.53.34980 > 172.20.2.77.80: Flags [S], seq 101042966, win 64240, options [mss 1460,sackOK,TS val 1430011627 ecr 0,nop,wscale 7], length

k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done

NODEIP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')      ' 
echo -e "http://$NODEIP:30003"

cilium hubble port-forward&
hubble status
hubble observe -f --protocol tcp --pod curl-pod

# 통신이 안되는 문제 해결하는 방법. 라우팅 수동 설정 또는 오버레이 네트워크
# 그래서 이러한 문제를 해결하기 위해 오버레이 네트워크의 경우에는 원본 패킷을 캡슐화해서 보내게된다. SNAT 처리하게됨
```

### encapsulation(VxLAN)
```sh
# Vxlan을 위한 커널 모듈 조회
grep -E 'CONFIG_VXLAN=y|CONFIG_VXLAN=m|CONFIG_GENEVE=y|CONFIG_GENEVE=m|CONFIG_FIB_RULES=y' /boot/config-$(uname -r)
CONFIG_FIB_RULES=y
CONFIG_VXLAN=m
CONFIG_GENEVE=m

# 커널 모듈 활성화
lsmod | grep -E 'vxlan|geneve'
modprobe vxlan

lsmod |grep vxlan
vxlan                 147456  0
ip6_udp_tunnel         16384  1 vxlan
udp_tunnel             36864  1 vxlan

# 워커 노드 동일한 설정 구성
for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i sudo modprobe vxlan ; echo; done
for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i sudo lsmod | grep -E 'vxlan|geneve' ; echo; done
vxlan                 147456  0
ip6_udp_tunnel         16384  1 vxlan
udp_tunnel             36864  1 vxlan

export WEBPOD1=$(kubectl get pod -l app=webpod --field-selector spec.nodeName=k8s-w1 -o jsonpath='{.items[0].status.podIP}')
echo $WEBPOD1

k exec -it curl-pod -- ping $WEBPOD1

# vxlan으로 재배포
helm upgrade cilium cilium/cilium --namespace kube-system --version 1.18.0 --reuse-values \
  --set routingMode=tunnel --set tunnelProtocol=vxlan \
  --set autoDirectNodeRoutes=false --set installNoConntrackIptablesRules=false

# natvie에서 vxlan으로 전환 과정에서 패킷이 실패한다.
k rollout restart -n kube-system ds/cilium
64 bytes from 172.20.1.219: icmp_seq=72 ttl=62 time=0.331 ms
From 172.20.0.192 icmp_seq=73 Time to live exceeded
From 172.20.0.192 icmp_seq=74 Time to live exceeded
64 bytes from 172.20.1.219: icmp_seq=75 ttl=63 time=0.572 ms
64 bytes from 172.20.1.219: icmp_seq=76 ttl=63 time=0.510 ms

# datapath_network가 overlay-vxlan으로 변경된 것을 확인할 수 있다.
cilium features status | grep datapath_network
Yes      cilium_feature_datapath_chaining_enabled                                mode=none                                         1        1       1
Yes      cilium_feature_datapath_config                                          mode=veth                                         1        1       1
Yes      cilium_feature_datapath_internet_protocol                               address_family=ipv4-only                          1        1       1
Yes      cilium_feature_datapath_network                                         mode=overlay-vxlan                                1        1       1

k exec -it -n kube-system ds/cilium -- cilium status | grep ^Routing
Routing:                 Network: Tunnel [vxlan]   Host: BPF

cilium config view | grep tunnel
routing-mode                                      tunnel
tunnel-protocol                                   vxlan
tunnel-source-port-range                          0-0

# 새로운 네트워크 인터페이스가 생성된 것을 확인할 수 있다.
# vxlan이 다른 노드와 통신할 때 패킷을 캡슐화해서 다른 노드에 보내게 된다.
ip -c addr show dev cilium_vxlan
26: cilium_vxlan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default
    link/ether 4e:a6:ba:17:99:ee brd ff:ff:ff:ff:ff:ff
    inet6 fe80::4ca6:baff:fe17:99ee/64 scope link
       valid_lft forever preferred_lft forever

for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i ip -c addr show dev cilium_vxlan ; echo; done

# 에전과는 다르게 다른 노드의 파드 CIDR가 라우팅 테이블에 추가되었다.
ip -c route | grep cilium_host
172.20.0.0/24 via 172.20.0.192 dev cilium_host proto kernel src 172.20.0.192
172.20.0.192 dev cilium_host proto kernel scope link
172.20.1.0/24 via 172.20.0.192 dev cilium_host proto kernel src 172.20.0.192 mtu 1450
172.20.2.0/24 via 172.20.0.192 dev cilium_host proto kernel src 172.20.0.192 mtu 1450

ip route get 172.20.1.10
172.20.1.10 dev cilium_host src 172.20.0.192 uid 0
    cache mtu 1450
ip route get 172.20.1.20
172.20.1.20 dev cilium_host src 172.20.0.192 uid 0
    cache mtu 
    
for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i ip -c route | grep cilium_host ; echo; done

export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w0  -o jsonpath='{.items[0].metadata.name}')
echo $CILIUMPOD0 $CILIUMPOD1 $CILIUMPOD2

# 각 노드별로 라우터 역할을 하는 ip 조회
k exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium status --all-addresses | grep router
k exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium status --all-addresses | grep router
k exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- cilium status --all-addresses | grep router
172.20.0.192 (router)
172.20.1.141 (router)
172.20.2.160 (router)

# cilium ip cacahe 목록 
k exec -n kube-system ds/cilium -- cilium-dbg bpf ipcache list
IP PREFIX/ADDRESS   IDENTITY
172.20.0.53/32      identity=2163 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.192/32     identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.211/32     identity=36329 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.1.219/32     identity=2219 encryptkey=0 tunnelendpoint=192.168.10.101 flags=hastunnel
172.20.2.160/32     identity=6 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel
10.0.2.15/32        identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.36/32      identity=2246 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.126/32     identity=2219 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.2.0/24       identity=2 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel
192.168.10.101/32   identity=6 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
192.168.20.100/32   identity=6 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.35/32      identity=6959 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.42/32      identity=59394 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.183/32     identity=38507 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.200/32     identity=6959 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.1.141/32     identity=6 encryptkey=0 tunnelendpoint=192.168.10.101 flags=hastunnel
172.20.0.48/32      identity=472 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.0.177/32     identity=7135 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
172.20.1.0/24       identity=2 encryptkey=0 tunnelendpoint=192.168.10.101 flags=hastunnel
172.20.2.77/32      identity=2219 encryptkey=0 tunnelendpoint=192.168.20.100 flags=hastunnel
192.168.10.100/32   identity=1 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
0.0.0.0/0           identity=2 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>

k exec -n kube-system ds/cilium -- cilium-dbg bpf socknat list
Socket Cookie   Backend -> Frontend
46636           192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)
4325            192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)
4576            192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)
38555           192.168.10.100:-27632 -> 10.96.217.172:-17663 (revnat=256)
4119            192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)
4238            192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)
43438           172.20.0.183:2600 -> 10.96.218.119:-17663 (revnat=768)
46846           172.20.0.183:2600 -> 10.96.218.119:-17663 (revnat=768)
4120            192.168.10.100:11033 -> 10.96.0.1:-17663 (revnat=4864)

###### 파드간 통신 확인 
k exec -it curl-pod -- curl webpod | grep Hostname
Hostname: webpod-697b545f57-rpxqc

k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'
Hostname: webpod-697b545f57-rpxqc
---
Hostname: webpod-697b545f57-2nk8p

export WEBPOD=$(kubectl get pod -l app=webpod --field-selector spec.nodeName=k8s-w0 -o jsonpath='{.items[0].status.podIP}')
echo $WEBPOD

# Router 
# eth1 으롤 들어온 패킷이 eth2으로 패킷이 전달되어 k8s-w0 노드에 전달된다 
tcpdump -i any udp port 8472 -nn

k exec -it curl-pod -- ping -c 2 -w 1 -W 1 $WEBPOD
PING 172.20.2.77 (172.20.2.77) 56(84) bytes of data.
64 bytes from 172.20.2.77: icmp_seq=1 ttl=63 time=0.881 ms

tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
18:28:44.681021 eth1  In  IP 192.168.10.100.43447 > 192.168.20.100.8472: OTV, flags [I] (0x08), overlay 0, instance 2163
IP 172.20.0.102 > 172.20.2.77: ICMP echo request, id 30, seq 1, length 64
18:28:44.681043 eth2  Out IP 192.168.10.100.43447 > 192.168.20.100.8472: OTV, flags [I] (0x08), overlay 0, instance 2163
IP 172.20.0.102 > 172.20.2.77: ICMP echo request, id 30, seq 1, length 64
18:28:44.681493 eth2  In  IP 192.168.20.100.43022 > 192.168.10.100.8472: OTV, flags [I] (0x08), overlay 0, instance 2219
IP 172.20.2.77 > 172.20.0.102: ICMP echo reply, id 30, seq 1, length 64
18:28:44.681499 eth1  Out IP 192.168.20.100.43022 > 192.168.10.100.8472: OTV, flags [I] (0x08), overlay 0, instance 2219
IP 172.20.2.77 > 172.20.0.102: ICMP echo reply, id 30, seq 1, length 64

k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# rOuter
# router는 3계층 ip에 대한 패킷만을 조회하구, 이후 상위 계층에 대해서는 조회하지 않는다.
# 패킷이 캡슐화되어 오버헤드가 발생 
tcpdump -i any udp port 8472 -w /tmp/vxlan.pcap
tshark -r /tmp/vxlan.pcap -d udp.port==8472,vxlan
termshark -r /tmp/vxlan.pcap
termshark -r /tmp/vxlan.pcap -d udp.port==8472,vxlan

hubble observe -f --protocol tcp --pod curl-pod
```

https://docs.cilium.io/en/stable/network/concepts/routing/


### Service LB-IPAM
LB 타입의 서비스 생성시 ip를 할당해주는 pool을 정의한다.

```sh
k get CiliumLoadBalancerIPPool -A

# LB IPAM 생성 
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"  # v1.17 : cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: "cilium-lb-ippool"
spec:
  blocks:
  - start: "192.168.10.211"
    stop:  "192.168.10.215"
EOF

# 약어 조회 
k api-resources | grep -i CiliumLoadBalancerIPPool
ciliumloadbalancerippools           ippools,ippool,lbippool,lbippools   cilium.io/v2                      false        CiliumLoadBalancerIPPool

# 정의한 것과 같이 5개의 가용 주소가 확인된다.
k get ippools
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cilium-lb-ippool   false      False         5               44s

# 기존 서비스 변경
k patch svc webpod -p '{"spec":{"type":"LoadBalancer"}}'

k get svc webpod -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
192.168.10.211

LBIP=$(kubectl get svc webpod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

k exec -it curl-pod -- curl -s $LBIP | grep -E 'Hostname|RemoteAddr'
Hostname: webpod-697b545f57-kf46p
RemoteAddr: 172.20.0.53:57674

# 앞서 ip를 할당하게 되어 현재는 4개가 사용가능하다.
k get ippools
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cilium-lb-ippool   false      False         4               31m

# 총 5개의 ip중 4개가 가용하며, 1개가 사용중이다.
k get ippools -o jsonpath='{.items[*].status.conditions[?(@.type!="cilium.io/PoolConflict")]}' | jq
{
  "lastTransitionTime": "2025-08-07T08:17:59Z",
  "message": "5",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsTotal"
}
{
  "lastTransitionTime": "2025-08-07T08:17:59Z",
  "message": "4",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsAvailable"
}
{
  "lastTransitionTime": "2025-08-07T08:17:59Z",
  "message": "1",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsUsed"
}

# cilium servcie IPAM에 의해서 192.168.10.211라는 가상의 IP를 할당받았다.
k get svc webpod -o jsonpath='{.status}' | jq
{
  "conditions": [
    {
      "lastTransitionTime": "2025-08-07T08:19:02Z",
      "message": "",
      "reason": "satisfied",
      "status": "True",
      "type": "cilium.io/IPAMRequestSatisfied"
    }
  ],
  "loadBalancer": {
    "ingress": [
      {
        "ip": "192.168.10.211",
        "ipMode": "VIP"
      }
    ]
  }
}

# Router
# k8s 클러스터 외부에서 접근가능한지 확인. timeout 에러가 발생한다. 왜냐하면 router 서버는 로드밸런서 주소에 대해서 알지 못하기 때문이다.
LBIP=192.168.10.211
curl --connect-timeout 1 $LBIP
curl: (28) Failed to connect to 192.168.10.211 port 80 after 1000 ms: Timeout was reached

arping -i eth1 $LBIP -c 1
ARPING 192.168.10.211
Timeout
--- 192.168.10.211 statistics ---
1 packets transmitted, 0 packets received, 100% unanswered (0 extra)

arping -i eth1 $LBIP -c 100000
ARPING 192.168.10.211
Timeout
--- 192.168.10.211 statistics ---
4 packets transmitted, 0 packets received, 100% unanswered (0 extra)
```
https://isovalent.com/blog/post/migrating-from-metallb-to-cilium/#load-balancer-ipam


### L2 Announement
제약사항
- IPv6 지원하지 않는다
- 로드밸런싱 기능이 동작하지 않는다. 단일 노드가 모든 트래픽을 수신받는다.
- externalTrafficPolicy:Local이 동작하지 않는다

```sh
# Router
# L2 Announement를 garp를 통해 노드의 mac 주소를 라우터 서버에 전덜하게 된다.
# MetalLB와 동일한 개념이다. ㄹ
arping -i eth1 $LBIP -c 100000
Timeout

helm upgrade cilium cilium/cilium --namespace kube-system --version 1.18.0 --reuse-values \
   --set l2announcements.enabled=true && watch -d kubectl get pod -A

k rollout restart -n kube-system ds/cilium

k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg config --all | grep EnableL2Announcements
EnableL2Announcements             : true

cilium config view | grep enable-l2
enable-l2-announcements                           true
enable-l2-neigh-discovery                         true

# 특정 서비스와 특정 노드 선출 
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"  # not v2
kind: CiliumL2AnnouncementPolicy
metadata:
  name: policy1
spec:
  serviceSelector:
    matchLabels:
      app: webpod
  nodeSelector:
    matchExpressions:
      - key: kubernetes.io/hostname
        operator: NotIn
        values:
          - k8s-w0
  interfaces:
  - ^eth[1-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

# 이후에 Router 서버에서 응답하게 된다.
60 bytes from 08:00:27:a2:cd:65 (192.168.10.211): index=0 time=229.166 usec

k -n kube-system get lease | grep "cilium-l2announce"
cilium-l2announce-default-webpod       k8s-ctr                                                                     55s

# 현재 스피커 노드 조회
k -n kube-system get lease/cilium-l2announce-default-webpod -o yaml | yq
{
  "apiVersion": "coordination.k8s.io/v1",
  "kind": "Lease",
  "metadata": {
    "creationTimestamp": "2025-08-08T04:49:06Z",
    "name": "cilium-l2announce-default-webpod",
    "namespace": "kube-system",
    "resourceVersion": "14439",
    "uid": "323110e6-5da5-4820-9d29-553c6022274b"
  },
  "spec": {
    "acquireTime": "2025-08-08T04:49:06.568316Z",
    "holderIdentity": "k8s-ctr",
    "leaseDurationSeconds": 15,
    "leaseTransitions": 0,
    "renewTime": "2025-08-08T04:50:10.682969Z"
  }
}

export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w0  -o jsonpath='{.items[0].metadata.name}')
echo $CILIUMPOD0 $CILIUMPOD1 $CILIUMPOD2

# Cilium 모든 파드에서 어느 IP에 대해서 어느 네트워크 인터페이스서 announce하는지 조회
k exec -n kube-system $CILIUMPOD0 -- cilium-dbg shell -- db/show l2-announce
IP               NetworkInterface
192.168.10.211   eth1
k exec -n kube-system $CILIUMPOD1 -- cilium-dbg shell -- db/show l2-announce
IP   NetworkInterface
k exec -n kube-system $CILIUMPOD2 -- cilium-dbg shell -- db/show l2-announce
IP   NetworkInterface

# arp시 k8s-ctr의 mac 주소를 확인할수 있다.
arping -i eth1 $LBIP -c 1000
ARPING 192.168.10.211
60 bytes from 08:00:27:a2:cd:65 (192.168.10.211): index=0 time=948.208 usec

curl --connect-timeout 1 $LBIP
Hostname: webpod-697b545f57-2nk8p
IP: 127.0.0.1
IP: ::1
IP: 172.20.2.77
IP: fe80::30b2:88ff:febe:3b36
RemoteAddr: 172.20.0.192:46844
GET / HTTP/1.1
Host: 192.168.10.211
User-Agent: curl/8.5.0
Accept: */*

# k8s-ctr ip와 211 ip가 동일한 mac 주소를 가진 것을 볼수 있다.
arp -a
? (192.168.10.100) at 08:00:27:a2:cd:65 [ether] on eth1
? (192.168.10.211) at 08:00:27:a2:cd:65 [ether] on eth1

curl -s $LBIP
Hostname: webpod-697b545f57-rpxqc
IP: 127.0.0.1
IP: ::1
IP: 172.20.0.126
IP: fe80::cc3b:51ff:fe8e:26ed
RemoteAddr: 192.168.10.200:34156
GET / HTTP/1.1
Host: 192.168.10.211
User-Agent: curl/8.5.0
Accept: */*

root@router:~# while true; do curl -s --connect-timeout 1 $LBIP | grep -E "RemoteAddr|Hostname"; sleep 0.1; done
Hostname: webpod-697b545f57-rpxqc
RemoteAddr: 192.168.10.200:48526
Hostname: webpod-697b545f57-kf46p
RemoteAddr: 172.20.0.192:48542

# Router 
while true; do curl -s --connect-timeout 1 $LBIP | grep Hostname; sleep 0.1; done

# 리더 노드 조회
k -n kube-system get lease | grep "cilium-l2announce"
cilium-l2announce-default-webpod       k8s-ctr                                                                     12m

# 리더 노드를 재시작하게 될 경우, 다른 노드가 전파하게 된다 
sshpass -p 'vagrant' ssh vagrant@k8s-ctr sudo reboot

# 현재는 w1 노도의 mac 주소와 211 ip의 주소가 동일하다.
arp -a
? (192.168.10.100) at 08:00:27:a2:cd:65 [ether] on eth1
? (192.168.10.211) at 08:00:27:e7:a8:0c [ether] on eth1
? (192.168.10.101) at 08:00:27:e7:a8:0c [ether] on eth1
```

https://docs.cilium.io/en/stable/network/l2-announcements/


### Service LB IPAM
```sh
# 샘플 App 배포 
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netshoot-web
  labels:
    app: netshoot-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: netshoot-web
  template:
    metadata:
      labels:
        app: netshoot-web
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: netshoot
          image: nicolaka/netshoot
          ports:
            - containerPort: 8080
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          command: ["sh", "-c"]
          args:
            - |
              while true; do 
                { echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK from \$POD_NAME"; } | nc -l -p 8080 -q 1;
              done
---
apiVersion: v1
kind: Service
metadata:
  name: netshoot-web
  labels:
    app: netshoot-web
spec:
  type: LoadBalancer
  selector:
    app: netshoot-web
  ports:
    - name: http
      port: 80      
      targetPort: 8080
EOF

k get svc netshoot-web -o wide
NAME           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE   SELECTOR
netshoot-web   LoadBalancer   10.96.56.141   192.168.10.212   80:30412/TCP   16s   app=netshoot-web

cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"  # not v2
kind: CiliumL2AnnouncementPolicy
metadata:
  name: policy2
spec:
  serviceSelector:
    matchLabels:
      app: netshoot-web
  nodeSelector:
    matchExpressions:
      - key: kubernetes.io/hostname
        operator: NotIn
        values:
          - k8s-w0
  interfaces:
  - ^eth[1-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

k -n kube-system get lease | grep "cilium-l2announce"
cilium-l2announce-default-netshoot-web   k8s-w1                                                                      22s
cilium-l2announce-default-webpod         k8s-w1                                                                      24m

k get svc netshoot-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
192.168.10.212

LB2IP=$(kubectl get svc netshoot-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s $LB2IP
OK from netshoot-web-5c59d94bd4-k7bjk

# 라우터 
LB2IP=192.168.10.212
arping -i eth1 $LB2IP -c 2
curl -s $LB2IP
ARPING 192.168.10.212
60 bytes from 08:00:27:e7:a8:0c (192.168.10.212): index=0 time=209.459 usec
60 bytes from 08:00:27:e7:a8:0c (192.168.10.212): index=1 time=333.083 usec

--- 192.168.10.212 statistics ---
2 packets transmitted, 2 packets received,   0% unanswered (0 extra)
rtt min/avg/max/std-dev = 0.209/0.271/0.333/0.062 ms
OK from netshoot-web-5c59d94bd4-j5hzw
```

### 특정 Servcie의 External IP 할당
```sh
k9s → svc → <e> edit
  annotations:
    "lbipam.cilium.io/ips": "192.168.10.215"

k get svc netshoot-web
netshoot-web   LoadBalancer   10.96.56.141   192.168.10.215   80:30412/TCP   31h

k get svc netshoot-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
LB2IP=$(kubectl get svc netshoot-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s $LB2IP
OK from netshoot-web-5c59d94bd4-clw2v
```

### Shraging Key 
External IP가 모자란 경우에 특정 포트르 지정하여 사용한다. 특정 IP를 공유하되, 각기 다른 포트를 사용한다.
```sh
# 서비스 추가 배포
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: netshoot-web2
  labels:
    app: netshoot-web
spec:
  type: LoadBalancer
  selector:
    app: netshoot-web
  ports:
    - name: http
      port: 8080      
      targetPort: 8080
EOF

k get svc -l app=netshoot-web
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
netshoot-web    LoadBalancer   10.96.56.141    192.168.10.215   80:30412/TCP     31h
netshoot-web2   LoadBalancer   10.96.225.170   192.168.10.212   8080:30983/TCP   12s

# 두 서비스 간에 동일한 ip로 배포하기 위해 하단의 annotations을 추가한다. 
k9s → svc → <e> edit 
  annotations:
    "lbipam.cilium.io/ips": "192.168.10.215"
    "lbipam.cilium.io/sharing-key": "1234"

# 동일한 ip를 할당받으면서 다른 포트를 사용하는 것을 확인할 수 있다.
k get svc -l app=netshoot-web
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
netshoot-web    LoadBalancer   10.96.56.141    192.168.10.215   80:30412/TCP     31h
netshoot-web2   LoadBalancer   10.96.225.170   192.168.10.215   8080:30983/TCP   91s

# l2announce를 수행하는 노드 조회
k -n kube-system get lease | grep "cilium-l2announce"
cilium-l2announce-default-netshoot-web    k8s-w1                                                                      31h
cilium-l2announce-default-netshoot-web2   k8s-w1                                                                      3m44s
cilium-l2announce-default-webpod          k8s-w1                                                                      32h

curl -s $LB2IP
OK from netshoot-web-5c59d94bd4-clw2v
curl -s $LB2IP:8080
OK from netshoot-web-5c59d94bd4-j5hzw

# router
LB2IP=192.168.10.215
arping -i eth1 $LB2IP -c 2
curl -s $LB2IP
curl -s $LB2IP:8080
```