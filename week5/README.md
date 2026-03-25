## [Cilium Study 1기] 5주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 5주차 스터디에 대한 정리 글입니다. 

## Cilium BGP Control Plane
Cilium 배포
```sh
# BGP를 적용한 설정 배포
helm upgrade cilium cilium/cilium --version 1.18 --namespace kube-system \
--set k8sServiceHost=192.168.10.100 --set k8sServicePort=6443 \
--set ipam.mode="cluster-pool" --set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} --set ipv4NativeRoutingCIDR=172.20.0.0/16 \
--set routingMode=native --set autoDirectNodeRoutes=false --set bgpControlPlane.enabled=true \
--set kubeProxyReplacement=true --set bpf.masquerade=true --set installNoConntrackIptablesRules=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set hubble.enabled=true --set hubble.relay.enabled=true --set hubble.ui.enabled=true \
--set hubble.ui.service.type=NodePort --set hubble.ui.service.nodePort=30003 \
--set prometheus.enabled=true --set operator.prometheus.enabled=true --set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
--set operator.replicas=1 --set debug.enabled=true 

# cilium 설정 조회
cilium config view | grep -i bgp
bgp-router-id-allocation-ip-pool
bgp-router-id-allocation-mode                     default
bgp-secrets-namespace                             kube-system
enable-bgp-control-plane                          true
enable-bgp-control-plane-status-report            true
```

Sample Application 배포 
```sh
# 샘플 애플리케이션 배포
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

# Application 상태 조회
k get deploy,svc,ep webpod -owide
k get endpointslices -l app=webpod
k get ciliumendpoints 
NAME                      SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
curl-pod                  4455                ready            172.20.0.42
webpod-697b545f57-7qssc   47820               ready            172.20.2.193
webpod-697b545f57-87w4m   47820               ready            172.20.1.194
webpod-697b545f57-f2s6w   47820               ready            172.20.0.148

k get pod -o wide
NAME                      READY   STATUS    RESTARTS   AGE    IP             NODE      NOMINATED NODE   READINESS GATES
curl-pod                  1/1     Running   0          106m   172.20.0.42    k8s-ctr   <none>           <none>
webpod-697b545f57-7qssc   1/1     Running   0          106m   172.20.2.193   k8s-w0    <none>           <none>
webpod-697b545f57-87w4m   1/1     Running   0          106m   172.20.1.194   k8s-w1    <none>           <none>
webpod-697b545f57-f2s6w   1/1     Running   0          106m   172.20.0.148   k8s-ctr   <none>           <none>

# k8s-ctr의 라우트 정보
ip -c route 
172.20.0.0/24 via 172.20.0.53 dev cilium_host proto kernel src 172.20.0.53
172.20.0.0/16 via 192.168.10.200 dev eth1 proto static
172.20.0.53 dev cilium_host proto kernel scope link

# 동일한 노드의 Pod에 대해서만 응답을 한다. 왜냐하면 autoDirectNodeRoutes를 false로 구성하여 라우팅 정보가 없기 때문이다.
k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'
---
---
---
Hostname: webpod-697b545f57-f2s6w
---
```

Cilium의 [BGP](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/) 요소
- `CiliumBGPClusterConfig`: Defines BGP instances and peer configurations that are applied to multiple nodes.
- `CiliumBGPPeerConfig`: A common set of BGP peering setting. It can be used across multiple peers.
- `CiliumBGPAdvertisement`: Defines prefixes that are injected into the BGP routing table.
- `CiliumBGPNodeConfigOverride`: Defines node-specific BGP configuration to provide a finer control.

```sh
vagrant ssh router 

ss -tnlp | grep -iE 'zebra|bgpd'
LISTEN 0      4096         0.0.0.0:179       0.0.0.0:*    users:(("bgpd",pid=4810,fd=22))
LISTEN 0      3          127.0.0.1:2605      0.0.0.0:*    users:(("bgpd",pid=4810,fd=18))
LISTEN 0      3          127.0.0.1:2601      0.0.0.0:*    users:(("zebra",pid=4805,fd=23))
LISTEN 0      4096            [::]:179          [::]:*    users:(("bgpd",pid=4810,fd=23))

ps -ef |grep frr
root        4792       1  0 03:10 ?        00:00:00 /usr/lib/frr/watchfrr -d -F traditional zebra bgpd staticd
frr         4805       1  0 03:10 ?        00:00:00 /usr/lib/frr/zebra -d -F traditional -A 127.0.0.1 -s 90000000
frr         4810       1  0 03:10 ?        00:00:00 /usr/lib/frr/bgpd -d -F traditional -A 127.0.0.1
frr         4817       1  0 03:10 ?        00:00:00 /usr/lib/frr/staticd -d -F traditional -A 127.0.0.1

# 
vtysh -c 'show running'
Current configuration:
!
frr version 8.4.4
frr defaults traditional
hostname router
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
router bgp 65000
 no bgp ebgp-requires-policy
 bgp graceful-restart
 bgp bestpath as-path multipath-relax
 !
 address-family ipv4 unicast
  network 10.10.1.0/24
  maximum-paths 4
 exit-address-family
exit
!
end

# frr의 bgp 설정 파일 조회
cat /etc/frr/frr.conf 
router bgp 65000
  bgp router-id
  bgp graceful-restart
  no bgp ebgp-requires-policy
  bgp bestpath as-path multipath-relax
  maximum-paths 4
  network 10.10.1.0/24

# BGP에 대한 정보가 아직 없다.
vtysh -c 'show ip bgp summary'
% No BGP neighbors found in VRF default

vtysh -c 'show ip bgp'
BGP table version is 1, local router ID is 192.168.20.200, vrf id 0 
Default local pref 100, local AS 65000
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found'

   Network          Next Hop            Metric LocPrf Weight Path
*> 10.10.1.0/24     0.0.0.0                  0         32768 i

Displayed  1 routes and 1 total paths

# router 
ip -c route
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.1.0/24 dev loop1 proto kernel scope link src 10.10.1.200
10.10.2.0/24 dev loop2 proto kernel scope link src 10.10.2.200
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.200
192.168.20.0/24 dev eth2 proto kernel scope link src 192.168.20.200

vtysh -c 'show ip route'
K>* 0.0.0.0/0 [0/100] via 10.0.2.2, eth0, src 10.0.2.15, 00:03:27
C>* 10.0.2.0/24 [0/100] is directly connected, eth0, 00:03:27
K>* 10.0.2.2/32 [0/100] is directly connected, eth0, 00:03:27
K>* 10.0.2.3/32 [0/100] is directly connected, eth0, 00:03:27
C>* 10.10.1.0/24 is directly connected, loop1, 00:03:27
C>* 10.10.2.0/24 is directly connected, loop2, 00:03:27
C>* 192.168.10.0/24 is directly connected, eth1, 00:03:27
C>* 192.168.20.0/24 is directly connected, eth2, 00:03:27

# BGP 네이버 생성
cat << EOF >> /etc/frr/frr.conf
  neighbor CILIUM peer-group
  neighbor CILIUM remote-as external
  neighbor 192.168.10.100 peer-group CILIUM
  neighbor 192.168.10.101 peer-group CILIUM
  neighbor 192.168.20.100 peer-group CILIUM 
EOF

# 설정 값 조회
cat  /etc/frr/frr.conf

# 설정 리로드 및 재시작
systemctl daemon-reexec && systemctl restart frr
systemctl status frr --no-pager --full

journalctl -u frr -f

# BGP 전파할 노드 라벨링
k label nodes k8s-ctr k8s-w0 k8s-w1 enable-bgp=true

# BGP 노드 조회
k get node -l enable-bgp=true
k8s-ctr   Ready    control-plane   122m   v1.33.2
k8s-w0    Ready    <none>          118m   v1.33.2
k8s-w1    Ready    <none>          121m   v1.33.2

# BGP 리소스 생성 
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "PodCIDR"
---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  ebgpMultihop: 2
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      "enable-bgp": "true"
  bgpInstances:
  - name: "instance-65001"
    localASN: 65001
    peers:
    - name: "tor-switch"
      peerASN: 65000
      peerAddress: 192.168.10.200  # router ip address
      peerConfigRef:
        name: "cilium-peer"
EOF

# cilium이 현재 연결된 세션 정보를 확인할 수 있다. ctr 노두의 51443 포트와 라우터 서버의 179랑 연결이 되어있다.
ss -tnlp | grep 179
ss -tnp | grep 179
ESTAB 0      0               192.168.10.100:51443          192.168.10.200:179   users:(("cilium-agent",pid=5771,fd=50))

# BGP 상태 조회
cilium bgp peers
Node      Local AS   Peer AS   Peer Address     Session State   Uptime   Family         Received   Advertised
k8s-ctr   65001      65000     192.168.10.200   established     33s      ipv4/unicast   4          2
k8s-w0    65001      65000     192.168.10.200   established     34s      ipv4/unicast   4          2
k8s-w1    65001      65000     192.168.10.200   established     34s      ipv4/unicast   4          2

cilium bgp routes available ipv4 unicast
Node      VRouter   Prefix          NextHop   Age   Attrs
k8s-ctr   65001     172.20.0.0/24   0.0.0.0   47s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w0    65001     172.20.2.0/24   0.0.0.0   47s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w1    65001     172.20.1.0/24   0.0.0.0   47s   [{Origin: i} {Nexthop: 0.0.0.0}]

k get ciliumbgpadvertisements,ciliumbgppeerconfigs,ciliumbgpclusterconfigs
NAME                                                  AGE
ciliumbgpadvertisement.cilium.io/bgp-advertisements   56s
NAME                                        AGE
ciliumbgppeerconfig.cilium.io/cilium-peer   56s
NAME                                          AGE
ciliumbgpclusterconfig.cilium.io/cilium-bgp   56s

k get ciliumbgpnodeconfigs -o yaml | yq |grep -i peering -A10
peeringState": "established",
                "routeCount": [
                  {
                    "advertised": 2,
                    "afi": "ipv4",
                    "received": 1,
                    "safi": "unicast"
                  }
                ]"

# Router
# bpg에 대한 정보를 수신했따.
journalctl -u frr -f
Aug 17 03:14:18 router systemd[1]: Started frr.service - FRRouting.
Aug 17 03:16:38 router bgpd[5071]: [M59KS-A3ZXZ] bgp_update_receive: rcvd End-of-RIB for IPv4 Unicast from 192.168.10.101 in vrf default
Aug 17 03:16:38 router bgpd[5071]: [M59KS-A3ZXZ] bgp_update_receive: rcvd End-of-RIB for IPv4 Unicast from 192.168.20.100 in vrf default
Aug 17 03:16:38 router bgpd[5071]: [M59KS-A3ZXZ] bgp_update_receive: rcvd End-of-RIB for IPv4 Unicast from 192.168.10.100 in vrf default

# Router
ip -c route | grep bgp
172.20.0.0/24 nhid 32 via 192.168.10.100 dev eth1 proto bgp metric 20
172.20.1.0/24 nhid 30 via 192.168.10.101 dev eth1 proto bgp metric 20
172.20.2.0/24 nhid 31 via 192.168.20.100 dev eth2 proto bgp metric 20

# Router
vtysh -c 'show ip bgp summary'
BGP router identifier 192.168.20.200, local AS number 65000 vrf-id 0
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
192.168.10.100  4      65001        63        66        0    0    0 00:03:00            1        4 N/A
192.168.10.101  4      65001        63        66        0    0    0 00:03:00            1        4 N/A
192.168.20.100  4      65001        63        66        0    0    0 00:03:00            1        4 N/A

# Router
vtysh -c 'show ip bgp'
   Network          Next Hop            Metric LocPrf Weight Path
*> 10.10.1.0/24     0.0.0.0                  0         32768 i
*> 172.20.0.0/24    192.168.10.100                         0 65001 i
*> 172.20.1.0/24    192.168.10.101                         0 65001 i
*> 172.20.2.0/24    192.168.20.100                         0 65001 i


# 파드간에 통신 정상 작동 확인
k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# k8s-ctr 
tcpdump -i eth1 tcp port 179 -w /tmp/bgp.pcap

# router의 frr 재시작
systemctl restart frr && journalctl -u frr -f

# 필터링 bgp.type == 2.
# 하지만 termshark를 사용할 때마다 k8s-ctr가 죽는다
termshark -r /tmp/bgp.pcap

# 확인 못했음
# cilium bgp routes
# ip -c route


# 특정 노드의 유지 보수할 경우
k drain k8s-w0 --ignore-daemonsets
k label nodes k8s-w0 enable-bgp=false --overwrite
k get node
k8s-ctr   Ready                      control-plane   8m44s   v1.33.2
k8s-w0    Ready,SchedulingDisabled   <none>          4m41s   v1.33.2
k8s-w1    Ready                      <none>          6m56s   v1.33.2

# bgp를 전파하는 k8s-w0 노드가 제거되었다.
k get ciliumbgpnodeconfigs
k8s-ctr   119s
k8s-w1    119s

cilium bgp routes
Node      VRouter   Prefix          NextHop   Age     Attrs
k8s-ctr   65001     172.20.0.0/24   0.0.0.0   2m31s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w1    65001     172.20.1.0/24   0.0.0.0   2m31s   [{Origin: i} {Nexthop: 0.0.0.0}]

cilium bgp peers
Node      Local AS   Peer AS   Peer Address     Session State   Uptime   Family         Received   Advertised
k8s-ctr   65001      65000     192.168.10.200   established     2m41s    ipv4/unicast   3          2
k8s-w1    65001      65000     192.168.10.200   established     2m42s    ipv4/unicast   3          2

# 복구 
k label nodes k8s-w0 enable-bgp=true --overwrite
k uncordon k8s-w0

# 파드 재준배
kubectl scale deployment webpod --replicas 0
kubectl scale deployment webpod --replicas 3

# 튜닝 가이드 
# https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-operation/#disabling-crd-status-report
# 대규모 클러스터인 경우 api-server에 부하를 유발할수 있기 때문에  bgp status reporting off  설정을 꺼준다
k get ciliumbgpnodeconfigs -o yaml | yq

helm upgrade cilium cilium/cilium --version 1.18.0 --namespace kube-system --reuse-values \
  --set bgpControlPlane.statusReport.enabled=false

k -n kube-system rollout restart ds/cilium
      "status": {}
```


![](https://cdn.sanity.io/images/xinsvxfu/production/3afbdce3468cab319c89ae2597fe2f35e1a23e0d-2112x1008.png?auto=format&q=80&fit=clip&w=2560)

로드밸랜서 IP로 BGP 광고
```sh
# BGP로 SVC IBPM을 광고하기 떄문에 노드의 네트워크 대역대가 아니더라도 통신이 가능하다.
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "cilium-pool"
spec:
  allowFirstLastIPs: "No"
  blocks:
  - cidr: "172.16.1.0/24"
EOF

k get ippool
NAME          DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cilium-pool   false      False         254             53s

# 기존 서비스 타입 변경 
k patch svc webpod -p '{"spec": {"type": "LoadBalancer"}}'
service/webpod patched

k get svc webpod
NAME     TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
webpod   LoadBalancer   10.96.121.166   172.16.1.1    80:32759/TCP   13m

k get ippool
NAME          DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cilium-pool   false      False         253             76s

kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
16   172.16.1.1:80/TCP       LoadBalancer   1 => 172.20.0.10:80/TCP (active)
                                            2 => 172.20.1.252:80/TCP (active)
                                            3 => 172.20.2.200:80/TCP (active)

k describe svc webpod | grep 'Traffic Policy'
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster

# 네트워크 욫어 조회
k get svc webpod -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
LBIP=$(kubectl get svc webpod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s $LBIP

# LB ip bgp를 통한 광고
# Service 유형의, LoadBalancerIP를, webpod과 일치하는 리소스를 전파한다.
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements-lb-exip-webpod
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:             
        matchExpressions:
          - { key: app, operator: In, values: [ webpod ] }
EOF

k get CiliumBGPAdvertisement
NAME                                AGE
bgp-advertisements                  14m
bgp-advertisements-lb-exip-webpod   21s

# bgp 라우트 정책 조회. 
k exec -it -n kube-system ds/cilium -- cilium-dbg bgp route-policies
VRouter   Policy Name                                             Type     Match Peers         Match Families   Match Prefixes (Min..Max Len)   RIB Action   Path Actions
65001     allow-local                                             import                                                                        accept
65001     tor-switch-ipv4-PodCIDR                                 export   192.168.10.200/32                    172.20.1.0/24 (24..24)          accept
65001     tor-switch-ipv4-Service-webpod-default-LoadBalancerIP   export   192.168.10.200/32                    172.16.1.1/32 (32..32)          accept

cilium bgp routes available ipv4 unicast
Node      VRouter   Prefix          NextHop   Age     Attrs
k8s-ctr   65001     172.16.1.1/32   0.0.0.0   2m21s   [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.0.0/24   0.0.0.0   8m36s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w0    65001     172.16.1.1/32   0.0.0.0   2m20s   [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.2.0/24   0.0.0.0   8m48s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w1    65001     172.16.1.1/32   0.0.0.0   2m20s   [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.1.0/24   0.0.0.0   8m48s   [{Origin: i} {Nexthop: 0.0.0.0}]


# router
# 로드밸런서에 대한 라우트 정보가 생겨났다.
ip -c addr 
172.16.1.1 nhid 38 proto bgp metric 20
	nexthop via 192.168.20.100 dev eth2 weight 1
	nexthop via 192.168.10.101 dev eth1 weight 1
	nexthop via 192.168.10.100 dev eth1 weight 1

vtysh -c 'show ip bgp'
*> 172.16.1.1/32    192.168.10.100                         0 65001 i
*=                  192.168.20.100                         0 65001 i
*=                  192.168.10.101                         0 65001 i

vtysh -c 'show ip bgp 172.16.1.1/32'
BGP routing table entry for 172.16.1.1/32, version 7
Paths: (3 available, best #1, table default)
  Advertised to non peer-group peers:
  192.168.10.100 192.168.10.101 192.168.20.100
  65001
    192.168.10.100 from 192.168.10.100 (192.168.10.100)
      Origin IGP, valid, external, multipath, best (Router ID)
      Last update: Sun Aug 17 05:30:56 2025
  65001
    192.168.20.100 from 192.168.20.100 (192.168.20.100)
      Origin IGP, valid, external, multipath
      Last update: Sun Aug 17 05:30:56 2025
  65001
    192.168.10.101 from 192.168.10.101 (192.168.10.101)
      Origin IGP, valid, external, multipath
      Last update: Sun Aug 17 05:30:56 2025

for i in {1..100};  do curl -s $LBIP | grep Hostname; done | sort | uniq -c | sort -nr
     41 Hostname: webpod-697b545f57-vgjgx
     30 Hostname: webpod-697b545f57-4nt47
     29 Hostname: webpod-697b545f57-9jsmh


k scale deployment webpod --replicas 2
k get pod -o wide
webpod-697b545f57-4nt47   1/1     Running   0          16m   172.20.2.200   k8s-w0    <none>           <none>
webpod-697b545f57-9jsmh   1/1     Running   0          16m   172.20.1.252   k8s-w1

# 파드의 개수가 줄어들었으나 전파하는 노드의 정보는 동일하다
cilium bgp routes
Node      VRouter   Prefix          NextHop   Age      Attrs
k8s-ctr   65001     172.16.1.1/32   0.0.0.0   6m28s    [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.0.0/24   0.0.0.0   12m43s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w0    65001     172.16.1.1/32   0.0.0.0   6m27s    [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.2.0/24   0.0.0.0   12m55s   [{Origin: i} {Nexthop: 0.0.0.0}]
k8s-w1    65001     172.16.1.1/32   0.0.0.0   6m27s    [{Origin: i} {Nexthop: 0.0.0.0}]
          65001     172.20.1.0/24   0.0.0.0   12m55s   [{Origin: i} {Nexthop: 0.0.0.0}]


# externalTrafficPolicy를 Local로 변경한 결과. webpod가 있는 노드에 대해서만 전파한다
k patch service webpod -p '{"spec":{"externalTrafficPolicy":"Local"}}'

# Router
vtysh -c 'show ip bgp'
*= 172.16.1.1/32    192.168.20.100                         0 65001 i
*>                  192.168.10.101                         0 65001 i
vtysh -c 'show ip bgp 172.16.1.1/32'
vtysh -c 'show ip route bgp'
ip -c r
172.16.1.1 nhid 42 proto bgp metric 20
	nexthop via 192.168.20.100 dev eth2 weight 1
	nexthop via 192.168.10.101 dev eth1 weight 1

# 반복 접근
# 동일한 노드에 대해서만 접근한다.
LBIP=172.16.1.1
curl -s $LBIP
for i in {1..100};  do curl -s $LBIP | grep Hostname; done | sort | uniq -c | sort -nr
while true; do curl -s $LBIP | egrep 'Hostname|RemoteAddr' ; sleep 0.1; done
Hostname: webpod-697b545f57-9jsmh
RemoteAddr: 192.168.20.200:33968
Hostname: webpod-697b545f57-9jsmh
RemoteAddr: 192.168.20.200:33984


# Router
# 리눅스 커널은 L3로 라우트한다. 만일 정교한 ip + port로 전달하고 한다면 fib_multipath_hash_policy를 설정한다.
sudo sysctl -w net.ipv4.fib_multipath_hash_policy=1
echo "net.ipv4.fib_multipath_hash_policy=1" >> /etc/sysctl.conf

for i in {1..100};  do curl -s $LBIP | grep Hostname; done | sort | uniq -c | sort -nr
     53 Hostname: webpod-697b545f57-4nt47
     47 Hostname: webpod-697b545f57-9jsmh

# k8s-ctr
k scale deployment webpod --replicas 3
k get pod -owide

# Router
ip -c r
172.16.1.1 nhid 47 proto bgp metric 20
	nexthop via 192.168.20.100 dev eth2 weight 1
	nexthop via 192.168.10.101 dev eth1 weight 1
	nexthop via 192.168.10.100 dev eth1 weight 1
for i in {1..100};  do curl -s $LBIP | grep Hostname; done | sort | uniq -c | sort -nr
     36 Hostname: webpod-697b545f57-4nt47
     33 Hostname: webpod-697b545f57-9jsmh
     31 Hostname: webpod-697b545f57-2nvcv
```

네트워크 인입 종류
- **BGP**(ECMP) + Service(LB EX-IP, ExternalTrafficPolicy:**Local**) + **SNAT** + **Random** 권장 방식 
- **BGP**(ECMP) + Service(LB EX-IP, ExternalTrafficPolicy:**Cluster**) + **DSR** + **Maglev** 비권장 방식

```sh
# 설정 조회
k exec -it -n kube-system ds/cilium -- cilium status --verbose
  Mode:                 SNAT
  Backend Selection:    Random
  Session Affinity:     Enabled

# geneve 적용
modprobe geneve # modprobe geneve
lsmod | grep -E 'vxlan|geneve'

# 워커 노드 geneve 적용
for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i sudo modprobe geneve ; echo; done
for i in w1 w0 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh vagrant@k8s-$i sudo lsmod | grep -E 'vxlan|geneve' ; echo; done

# 
helm upgrade cilium cilium/cilium --version 1.18.0 --namespace kube-system --reuse-values \
  --set tunnelProtocol=geneve --set loadBalancer.mode=dsr --set loadBalancer.dsrDispatch=geneve \
  --set loadBalancer.algorithm=maglev

k -n kube-system rollout restart ds/cilium

kubectl exec -it -n kube-system ds/cilium -- cilium status --verbose |grep -E 'geneve|Maglev|DSR'
  Mode:                  DSR
    DSR Dispatch Mode:   Geneve
  Backend Selection:     Maglev (Table Size: 16381

kubectl patch svc webpod -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'

# 모든 k8s 노드 실행
tcpdump -i eth1 -w /tmp/dsr.pcap

# router
curl -s $LBIP

# Hosts
vagrant plugin install vagrant-scp
vagrant scp k8s-ctr:/tmp/dsr.pcap .
```

노드별 입입 구성 
```sh
# 노드별 라베 그룹화
kubectl label nodes k8s-ctr k8s-w1 az1=true
kubectl label nodes k8s-w0         az2=true

# 확인
kubectl get node -l az1=true
kubectl get node -l az2=true

# 새 서비스 배포 
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

kubectl get svc,ep netshoot-web
kubectl get ippool

# Router 
# 라우팅 정보가 전부 삭제된다
watch "vtysh -c 'show ip route bgp'"

# 기존 BGP 설정 제거
k delete ciliumbgpadvertisements,ciliumbgppeerconfigs,ciliumbgpclusterconfigs --all

# 새 서비스 배포 
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: service1-bgp-advertisements
  labels:
    advertise: service1-bgp
spec:
  advertisements:
    - advertisementType: "PodCIDR"
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:             
        matchExpressions:
          - { key: az1, operator: In, values: [ "true" ] }
---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: service1-cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  ebgpMultihop: 2
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: service1-bgp
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: service1-cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      "az1": "true"
  bgpInstances:
  - name: "instance-65001"
    localASN: 65001
    peers:
    - name: "tor-switch"
      peerASN: 65000
      peerAddress: 192.168.10.200  # router ip address
      peerConfigRef:
        name: "service1-cilium-peer"
EOF

# 라우터
watch "vtysh -c 'show ip route bgp'"
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:00:56
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:00:56

# 라벨 추가
kubectl label service webpod az1=true

watch "vtysh -c 'show ip route bgp'"
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:00:11
  *                      via 192.168.10.101, eth1, weight 1, 00:00:11
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:01:38
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:01:38

# 서비스 2 배포 
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: service2-bgp-advertisements
  labels:
    advertise: service2-bgp
spec:
  advertisements:
    - advertisementType: "PodCIDR"
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:             
        matchExpressions:
          - { key: az2, operator: In, values: [ "true" ] }
---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: service2-cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  ebgpMultihop: 2
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: service2-bgp
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: service2-cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      "az2": "true"
  bgpInstances:
  - name: "instance-65001"
    localASN: 65001
    peers:
    - name: "tor-switch"
      peerASN: 65000
      peerAddress: 192.168.10.200  # router ip address
      peerConfigRef:
        name: "service2-cilium-peer"
EOF

watch "vtysh -c 'show ip route bgp'"
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:02:22
  *                      via 192.168.10.101, eth1, weight 1, 00:02:22
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:03:49
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:03:49
B>* 172.20.2.0/24 [20/0] via 192.168.20.100, eth2, weight 1, 00:00:30

kubectl label service netshoot-web az2=true
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:02:54
  *                      via 192.168.10.101, eth1, weight 1, 00:02:54
B>* 172.16.1.2/32 [20/0] via 192.168.20.100, eth2, weight 1, 00:00:09
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:04:21
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:04:21
B>* 172.20.2.0/24 [20/0] via 192.168.20.100, eth2, weight 1, 00:01:02

kubectl patch service netshoot-web -p '{"spec":{"externalTrafficPolicy":"Local"}}'
kubectl scale deployment netshoot-web --replicas 1
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:03:25
  *                      via 192.168.10.101, eth1, weight 1, 00:03:25
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:04:52
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:04:52
B>* 172.20.2.0/24 [20/0] via 192.168.20.100, eth2, weight 1, 00:01:33

kubectl label nodes k8s-w1 az2=true
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:04:17
  *                      via 192.168.10.101, eth1, weight 1, 00:04:17
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:05:44
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:05:44
B>* 172.20.2.0/24 [20/0] via 192.168.20.100, eth2, weight 1, 00:02:25

kubectl label nodes k8s-w1 az1-
B>* 172.16.1.1/32 [20/0] via 192.168.10.100, eth1, weight 1, 00:00:10
B>* 172.20.0.0/24 [20/0] via 192.168.10.100, eth1, weight 1, 00:06:08
B>* 172.20.1.0/24 [20/0] via 192.168.10.101, eth1, weight 1, 00:00:07
B>* 172.20.2.0/24 [20/0] via 192.168.20.100, eth2, weight 1, 00:02:49

kubectl get node -l az1=true
kubectl get node -l az2=true
NAME      STATUS   ROLES           AGE   VERSION
k8s-ctr   Ready    control-plane   58m   v1.33.2

NAME     STATUS   ROLES    AGE   VERSION
k8s-w0   Ready    <none>   54m   v1.33.2
k8s-w1   Ready    <none>   56m   v1.33.2
```

## Kind
Kind 설치 및 유용한 플러그인 설치
```sh
brew install kind
brew install kubernetes-cli
brew install krew
brew install kube-ps1
brew install kubectx
brew install helm
brew install kubecolor

# 설치 조회
kind --version
kubectl version --client=true
helm version

# 단축키 설정 
echo "alias kubectl=kubecolor" >> ~/.zshrc
echo "alias kubectl=kubecolor" >> ~/.zshrc
echo "compdef kubecolor=kubectl" >> ~/.zshrc
```

Cluster 배포
```sh
docker ps

kind create cluster --name myk8s --image kindest/node:v1.32.2 --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
  - containerPort: 30001
    hostPort: 30001
  - containerPort: 30002
    hostPort: 30002
  - containerPort: 30003
    hostPort: 30003
- role: worker
- role: worker
- role: worker
EOF

# 노드 조회
kind get nodes --name myk8s
kubens default

# kind 는 별도 도커 네트워크 생성 후 사용 : 기본값 172.18.0.0/16
docker network ls
NETWORK ID     NAME            DRIVER    SCOPE
10d8011410ad   bridge          bridge    local
b832a580e3bf   host            host      local
e63730b2d612   kind            bridge    local

docker inspect kind | jq
    "Subnet": "172.19.0.0/16",
    "Gateway": "172.19.0.1"

# k8s api 주소 확인
k cluster-info
Kubernetes control plane is running at https://127.0.0.1:53890

# 노드 정보 확인
k get node -o wide
myk8s-control-plane   Ready    control-plane   3m19s   v1.32.2   172.19.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.0.3
myk8s-worker          Ready    <none>          3m10s   v1.32.2   172.19.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.0.3
...

# 파드 정보 확인
k get pod -A -o wide
kube-system          kindnet-g8fjh                                 1/1     Running   0          3m41s   172.19.0.2   myk8s-worker          <none>           <none>
kube-system          kindnet-k8s2q                                 1/1     Running   0          3m40s   172.19.0.5   myk8s-worker2         <none>           <none>
kube-system          kindnet-mj6zn                                 1/1     Running   0          3m43s   172.19.0.4   myk8s-control-plane   <none>           <none>
kube-system          kindnet-wnxv4

k get ns
NAME                 STATUS   AGE
default              Active   4m19s
kube-node-lease      Active   4m19s
kube-public          Active   4m19s
kube-system          Active   4m19s
local-path-storage   Active   4m15s

docker ps
docker images
docker exec -it myk8s-control-plane ss -tnlp

# 디버그용 내용 출력에 ~/.kube/config 권한 인증 로드
kubectl get pod -v6

# kubeconfig 조회
cat ~/.kube/config

# 클러스터 삭제
kind delete cluster --name myk8s
docker ps

# kubeconfig 조회. kubeconfig 내용이 존재하지 않는다.
cat ~/.kube/config
```

## Cluseter Mesh

Cluster 배포
```sh
# West 클러스터 배포
kind create cluster --name west --image kindest/node:v1.33.2 --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000 # sample apps
    hostPort: 30000
  - containerPort: 30001 # hubble ui
    hostPort: 30001
- role: worker
  extraPortMappings:
  - containerPort: 30002 # sample apps
    hostPort: 30002
networking:
  podSubnet: "10.0.0.0/16"
  serviceSubnet: "10.2.0.0/16"
  disableDefaultCNI: true
  kubeProxyMode: none
EOF

# 설치 및 노드 조회
kubectl ctx
kind-west

k get node
NAME                 STATUS     ROLES           AGE    VERSION
west-control-plane   NotReady   control-plane   103s   v1.33.2
west-worker          NotReady   <none>          89s    v1.33.2

k get pods -A 

# 노드 여러 도구 설치
docker exec -it west-control-plane sh -c 'apt update && apt install tree psmisc lsof wget net-tools dnsutils tcpdump ngrep iputils-ping git -y'
docker exec -it west-worker sh -c 'apt update && apt install tree psmisc lsof wget net-tools dnsutils tcpdump ngrep iputils-ping git -y'

# East 배포
kind create cluster --name east --image kindest/node:v1.33.2 --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 31000 # sample apps
    hostPort: 31000
  - containerPort: 31001 # hubble ui
    hostPort: 31001
- role: worker
  extraPortMappings:
  - containerPort: 31002 # sample apps
    hostPort: 31002
networking:
  podSubnet: "10.1.0.0/16"
  serviceSubnet: "10.3.0.0/16"
  disableDefaultCNI: true
  kubeProxyMode: none
EOF

# kubeconfig를 통해 여러 클러스터 구성 확인 
k config get-contexts 
CURRENT   NAME        CLUSTER     AUTHINFO    NAMESPACE
*         kind-east   kind-east   kind-east
          kind-west   kind-west   kind-west
          minikube    minikube    minikube    default

# 클러스터 변경
k config set-context kind-east

k get node -v=6 --context kind-east
NAME                 STATUS     ROLES           AGE   VERSION
east-control-plane   NotReady   control-plane   61s   v1.33.2
east-worker          NotReady   <none>          47s   v1.33.2

k get node -v=6
k get node -v=6 --context kind-west
NAME                 STATUS     ROLES           AGE     VERSION
west-control-plane   NotReady   control-plane   4m52s   v1.33.2
west-worker          NotReady   <none>          4m38s   v1.33.2

cat ~/.kube/config

kubectl get pod -A
kubectl get pod -A --context kind-west

# 노드 여러 도구 설치
docker exec -it east-control-plane sh -c 'apt update && apt install tree psmisc lsof wget net-tools dnsutils tcpdump ngrep iputils-ping git -y'
docker exec -it east-worker sh -c 'apt update && apt install tree psmisc lsof wget net-tools dnsutils tcpdump ngrep iputils-ping git -y'

# 단축키 지정
alias kwest='kubectl --context kind-west'
alias keast='kubectl --context kind-east'

kwest get node -owide
keast get node -owide
```

Cilum 배포
```sh
brew install cilium-cli

# helm 설정 출력. 실제로 배포하지 않는다.
cilium install --version 1.17.6 --set ipam.mode=kubernetes \
--set kubeProxyReplacement=true --set bpf.masquerade=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set operator.replicas=1 --set debug.enabled=true \
--set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.0.0.0/16 \
--set ipMasqAgent.enabled=true --set ipMasqAgent.config.nonMasqueradeCIDRs='{10.1.0.0/16}' \
--set cluster.name=west --set cluster.id=1 \
--context kind-west --dry-run-helm-values

# west 배포
# cluset의 이름과 고유값을 지정한다.
cilium install --version 1.17.6 --set ipam.mode=kubernetes \
--set kubeProxyReplacement=true --set bpf.masquerade=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set operator.replicas=1 --set debug.enabled=true \
--set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.0.0.0/16 \
--set ipMasqAgent.enabled=true --set ipMasqAgent.config.nonMasqueradeCIDRs='{10.1.0.0/16}' \
--set cluster.name=west --set cluster.id=1 \
--context kind-west

# east
cilium install --version 1.17.6 --set ipam.mode=kubernetes \
--set kubeProxyReplacement=true --set bpf.masquerade=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set operator.replicas=1 --set debug.enabled=true \
--set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.1.0.0/16 \
--set ipMasqAgent.enabled=true --set ipMasqAgent.config.nonMasqueradeCIDRs='{10.0.0.0/16}' \
--set cluster.name=east --set cluster.id=2 \
--context kind-east

# 파드 상태 조회. cilium 배포로 모든 파드가 Running 상태이다
kwest get pod -A && keast get pod -A
kube-system          kube-controller-manager-west-control-plane   1/1     Running   0          8m58s
kube-system          kube-scheduler-west-control-plane            1/1     Running   0          8m58s
local-path-storage   local-path-provisioner-7dc846544d-qgxn4      1/1     Running   0          8m51s
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
kube-system          cilium-cxvbg                                 1/1     Running   0          54s
kube-system          cilium-envoy-kwtg2                           1/1     Running   0          54s

# cluster 별 cilium 상태 조회
cilium status --context kind-east
cilium status --context kind-west

# cluster 별 설정 조회
cilium config view --context kind-west
cilium config view --context kind-east
kwest exec -it -n kube-system ds/cilium -- cilium status --verbose
keast exec -it -n kube-system ds/cilium -- cilium status --verbose

# 파드 CIDR 조회
kwest -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf ipmasq list
IP PREFIX/ADDRESS
10.1.0.0/16
169.254.0.0/16

# 파드 CIDR 조회
keast -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf ipmasq list
IP PREFIX/ADDRESS
10.0.0.0/16
169.254.0.0/16

# 두 클러스터 모두 기본 도메인을 사용한다
kubectl describe cm -n kube-system coredns --context kind-west | grep kubernetes
    kubernetes cluster.local in-addr.arpa ip6.arpa {
kubectl describe cm -n kube-system coredns --context kind-west | grep kubernetes
    kubernetes cluster.local in-addr.arpa ip6.arpa {

# k9s의 경우도 동일한 옵션 사용
k9s --context kind-west
k9s --context kind-east
```

CluseterMesh 구성
```sh
# 신기한 점은 ClusterMesh을 native 라우팅과 같은 네트워크 대인 경우 자동으로 라우팅을 주입한다. 
docker exec -it west-control-plane ip -c route
docker exec -it west-worker ip -c route
docker exec -it east-control-plane ip -c route
docker exec -it east-worker ip -c route

# cilium cluster name 및 id 조회
cilium config view --context kind-west |grep cluster-
cluster-id                                        1
cluster-name                                      west

cilium config view --context kind-east |grep cluster-
cluster-id                                        2
cluster-name                                      east


# cilium간에 cluster mesh를 구성하기 위해 동일한 ca를 사용한다. 이를 위해서 특정 cilium ca를 삭제 후 나머지 클러스터의 cilium ca를 복제한다.
keast get secret -n kube-system cilium-ca
keast delete secret -n kube-system cilium-ca

kubectl --context kind-west get secret -n kube-system cilium-ca -o yaml | \
kubectl --context kind-east create -f -

keast get secret -n kube-system cilium-ca
cilium-ca   Opaque   2      4s

cilium clustermesh status --context kind-west --wait  
cilium clustermesh status --context kind-east --wait
⌛ Waiting (0s) for access information: unable to get clustermesh service "clustermesh-apiserver": services "clustermesh-apiserver" not found

# cluster mesh를 Nodeport 타입의 서비스로 활성화한다. 권장하는 타입의 로드밸런서이다.
cilium clustermesh enable --service-type NodePort --enable-kvstoremesh=false --context kind-west
cilium clustermesh enable --service-type NodePort --enable-kvstoremesh=false --context kind-east

# clustermesh-apiserver를 위한 파드가 생성되었다.
kwest get pod -n kube-system -owide | grep clustermesh
clustermesh-apiserver-5cf45db9cc-w9hjt       2/2     Running     0          62s   10.0.1.230   west-worker          <none>           <none>
clustermesh-apiserver-generate-certs-t2kxt   0/1     Completed   0          62s   172.19.0.2   west-worker          <none>           <none>

kwest get svc,ep -n kube-system clustermesh-apiserver --context kind-west
NAME                            TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)          AGE
service/clustermesh-apiserver   NodePort   10.2.10.77   <none>        2379:32379/TCP   43s
NAME                              ENDPOINTS         AGE
endpoints/clustermesh-apiserver   10.0.1.230:2379   43s

# 클러스터 연동 
cilium clustermesh connect --context kind-west --destination-context kind-east

# 연동 조회
cilium clustermesh status --context kind-east --wait
cilium clustermesh status --context kind-west --wait
⚠️  Service type NodePort detected! Service may fail when nodes are removed from the cluster!
✅ Service "clustermesh-apiserver" of type "NodePort" found
✅ Cluster access information is available:
  - 172.19.0.3:32379
✅ Deployment clustermesh-apiserver is ready
ℹ️  KVStoreMesh is disabled

✅ All 2 nodes are connected to all clusters [min:1 / avg:1.0 / max:1]

🔌 Cluster Connections:
  - east: 2/2 configured, 2/2 connected

🔀 Global services: [ min:0 / avg:0.0 / max:0 ]

# 다른 클러스터에 대한 정보 그리고 TLS, ETCD에 대한 정보를 출력한다.cilium status --context kind-west
kubectl exec -it -n kube-system ds/cilium -c cilium-agent --context kind-west -- cilium-dbg troubleshoot clustermesh
kubectl exec -it -n kube-system ds/cilium -c cilium-agent --context kind-east -- cilium-dbg troubleshoot clustermesh

cilium status --context kind-west
Deployment             clustermesh-apiserver    Desired: 1, Ready: 1/1, Available: 1/1
Cluster Pods:          4/4 managed by Cilium
...

keast exec -it -n kube-system ds/cilium -- cilium status --verbose
ClusterMesh:   1/1 remote clusters ready, 0 global-services
   west: ready, 2 nodes, 4 endpoints, 3 identities, 0 services, 0 MCS-API service exports, 0 reconnections (last: never)
   └  etcd: 1/1 connected, leases=0, lock leases=0, has-quorum=true: endpoint status checks are disabled, ID: 9f649a615d34326f
   └  remote configuration: expected=true, retrieved=true, cluster-id=1, kvstoremesh=false, sync-canaries=true, service-exports=disabled

# helm에 대한 값 출력 
helm get values -n kube-system cilium --kube-context kind-west 
cluster:
  id: 1
  name: west
clustermesh:
  apiserver:
    kvstoremesh:
      enabled: false
    service:
      type: NodePort
    tls:
      auto:
        enabled: true
        method: cronJob
        schedule: 0 0 1 */4 *
  config:
    clusters:
    - ips:
      - 172.19.0.4
      name: east
      port: 32379
    enabled: true
  useAPIServer: true


# 라우팅 정보 조회 시 두 클러스터간에 각 노드에 대한 라우트 정보를 가지고 있따.
docker exec -it west-control-plane ip -c route
docker exec -it west-worker ip -c route
docker exec -it east-control-plane ip -c route
docker exec -it east-worker ip -c route

# 허블 활성화
cilium hubble enable --ui --relay --context kind-west
cilium hubble enable --ui --relay --context kind-east
```

Sample Application 배포
```sh
cat << EOF | kubectl apply --context kind-west -f -
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

cat << EOF | kubectl apply --context kind-east -f -
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

# 파드 ip 조회
kwest get pod -owide && keast get pod -owide
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE          NOMINATED NODE   READINESS GATES
curl-pod   1/1     Running   0          53s   10.0.1.188   west-worker   <none>           <none>
NAME       READY   STATUS    RESTARTS   AGE   IP          NODE          NOMINATED NODE   READINESS GATES
curl-pod   1/1     Running   0          53s   10.1.1.81   east-worker   <none>           <none>

# 두 클러스터 간에 icmp 응답 확인
kubectl exec -it curl-pod --context kind-west -- ping -c 1 10.1.1.81
kubectl exec -it curl-pod --context kind-west -- ping 10.0.1.188

# 두 클러스터 간에 어떠한 NAT 처리 없이 파드로 바로 통신하는 것을 확인할수 있다.
kubectl exec -it curl-pod --context kind-east -- tcpdump -i eth0 -nn
kubectl exec -it curl-pod --context kind-east -- ping -c 1 10.0.1.188
19:14:19.801251 IP 10.1.1.81 > 10.0.1.188: ICMP echo request, id 3, seq 1, length 64
19:14:19.801432 IP 10.0.1.188 > 10.1.1.81: ICMP echo reply, id 3, seq 1, length 64


# 서비스 및 애플리케이션 생성 
cat << EOF | kubectl apply --context kind-west -f -
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
  annotations:
    service.cilium.io/global: "true"
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

cat << EOF | kubectl apply --context kind-east -f -
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
  annotations:
    service.cilium.io/global: "true"
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

kwest get svc,ep webpod && keast get svc,ep webpod

# 만일 현재 k8s cluseter에 파드가 없더라도 다른 클러스터의 파드로 요청을 보낼수가 있다.
kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
keast exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.0.1.155:80/TCP (active)
                                           2 => 10.0.1.117:80/TCP (active)
                                           3 => 10.1.1.179:80/TCP (active)
                                           4 => 10.1.1.27:80/TCP (active)

# global으로 설정이 되어있기 때문이다.
kwest describe svc webpod | grep Annotations -A1
Annotations:              service.cilium.io/global: true
Selector:                 app=webpod

# 요청 반복 
kubectl exec -it curl-pod --context kind-west -- sh -c 'while true; do curl -s --connect-timeout 1 webpod ; sleep 1; echo "---"; done;'
kubectl exec -it curl-pod --context kind-east -- sh -c 'while true; do curl -s --connect-timeout 1 webpod ; sleep 1; echo "---"; done;'

# 다른 클러스터의 파드로 통신이 간다.
kwest scale deployment webpod --replicas 0
kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.1.1.179:80/TCP (active)
                                           2 => 10.1.1.27:80/TCP (active)



# 현재 k8s 클러스터를 우선으로 하여 요청을 전달한다. 말인 즉슨 현재 클러스터에서 파드가 없을 경우에는 다른 클러스터로 요청을 전달하게 된다.
kwest annotate service webpod service.cilium.io/affinity=local --overwrite
kwest describe svc webpod | grep Annotations -A3

kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.1.1.179:80/TCP (active)
                                           2 => 10.1.1.27:80/TCP (active)
                                           3 => 10.0.1.234:80/TCP (active) (preferred)
                                           4 => 10.0.1.128:80/TCP (active) (preferred)

kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.1.1.179:80/TCP (active)
                                           2 => 10.1.1.27:80/TCP (active)


# local과 반대되는 개념으로 다른 클러스터를 우선한다.
kwest annotate service webpod service.cilium.io/affinity=remote --overwrite
kwest describe svc webpod | grep Annotations -A3
Annotations:              service.cilium.io/affinity: remote
                          service.cilium.io/global: true

kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.1.1.179:80/TCP (active) (preferred)
                                           2 => 10.1.1.27:80/TCP (active) (preferred)
                                           3 => 10.0.1.77:80/TCP (active)
                                           4 => 10.0.1.253:80/TCP (active)



# 상태 원복 
kwest annotate service webpod service.cilium.io/affinity=local --overwrite
keast annotate service webpod service.cilium.io/affinity=local --overwrite

kest describe svc webpod | grep Annotations -A3
Annotations:              service.cilium.io/affinity: local
                          service.cilium.io/global: true

# shared를 false로 하면 파드 ip에 대한 정보를 다른 클러스터에 공유하지 않는다.
kwest annotate service webpod service.cilium.io/shared=false
service/webpod annotated

kwest describe svc webpod | grep Annotations -A3
Annotations:              service.cilium.io/affinity: local
                          service.cilium.io/global: true
                          service.cilium.io/shared: false
Selector:                 app=webpod

# west 클러스터는 4개의 파드에 대한 정보를 가지고 있지만, east는 2개의 파드 정보만을 출력한다.
kwest exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
keast exec -it -n kube-system ds/cilium -c cilium-agent -- cilium service list --clustermesh-affinity
9    10.2.183.236:80/TCP    ClusterIP      1 => 10.1.1.179:80/TCP (active)
                                           2 => 10.1.1.27:80/TCP (active)
                                           3 => 10.0.1.77:80/TCP (active) (preferred)
                                           4 => 10.0.1.253:80/TCP (active) (preferred)

11   10.3.191.80:80/TCP      ClusterIP      1 => 10.1.1.179:80/TCP (active) (preferred)
                                            2 => 10.1.1.27:80/TCP (active) (preferred)
```


## krew [pexec](https://github.com/ssup2/kpexec)
파드를 생성하게 되면 보안적인 이유로 bash를 제거한다. 하지만 해당 플러그인을 통해 우회해서 bash를 사용할 수 있다.

```sh
brew install ssup2/tap/kpexec

k exec -it -n kube-system clustermesh-apiserver-5cf45db9cc-hsqj5 -- bash
Defaulted container "etcd" out of: etcd, apiserver, etcd-init (init)
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "01c9b126fb9c2720a9d6c662060687a7c57279d0431f2f85cdf36eb6bbdfb260": OCI runtime exec failed: exec failed: unable to start container process: exec: "bash": executable file not found in $PATH

kubectl get pod -n kube-system -l k8s-app=clustermesh-apiserver
DPOD=clustermesh-apiserver-5cf45db9cc-h2vtp

# 파드에서 실행중인 프로세스에 대한 정보, 실행시 주입된 설정 및 포트등 다양한 정보를 확인할 수 있다. 
kubectl pexec clustermesh-apiserver-5cf45db9cc-hsqj5 -it -T -n kube-system -c etcd -- bash
ps -ef -T -o pid,ppid,comm,args
ps -ef -T -o args
cat /proc/1/cmdline ; echo
ss -tnlp
ss -tnp

kubectl pexec $DPOD -it -T -n kube-system -c apiserver -- bash
ps -ef -T -o pid,ppid,comm,args

# 클러스터 삭제 
kind delete cluster --name west && kind delete cluster --name east && docker rm -f mypc
```

