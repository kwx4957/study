## [Cilium Study 1기] 6주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 6주차 스터디에 대한 정리 글입니다. 

## [PWRU](https://github.com/cilium/pwru)

PWRU 설치
```sh
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
wget https://github.com/cilium/pwru/releases/download/v1.0.10/pwru-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar -xvzf pwru-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
mv pwru /usr/local/bin/pwru >/dev/null 2>&1

# 설치 확인
pwru -h

# pwru 패킷 모니터링 시작 
pwru --output-tuple 'dst host 1.1.1.1 and dst port 80 and tcp'

# 패킷 차단 설정 
iptables -t filter -I OUTPUT 1 -m tcp --proto tcp --dst 1.1.1.1/32 -j DROP

curl 1.1.1.1 -v

# 결과
2025/08/23 22:28:16 Attaching kprobes (via kprobe)...
1667 / 1667 [------------------------------------------------------------------------] 100.00% 4010 p/s
2025/08/23 22:28:16 Attached (ignored 5)
2025/08/23 22:28:16 Listening for events..
SKB                CPU PROCESS          NETNS      MARK/x        IFACE       PROTO  MTU   LEN   TUPLE FUNC
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0000 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) __ip_local_out
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) nf_hook_slow
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) kfree_skb_reason(SKB_DROP_REASON_NETFILTER_DROP)
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) skb_release_head_state
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 0     60    10.0.2.15:54448->1.1.1.1:80(tcp) tcp_wfree
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 0     60    10.0.2.15:54448->1.1.1.1:80(tcp) skb_release_data
0xffff00001603cae8 1   ~r/bin/curl:8493 4026531840 0               0         0x0800 0     60    10.0.2.15:54448->1.1.1.1:80(tcp) kfree_skbmem
0xffff00001603cae8 1   <empty>:0        4026531840 0               0         0x0800 0     60    10.0.2.15:54448->1.1.1.1:80(tcp) __skb_clone
0xffff00001603cae8 1   <empty>:0        0          0               0         0x0800 0     60    10.0.2.15:54448->1.1.1.1:80(tcp) __copy_skb_header
0xffff00001603cae8 1   <empty>:0        4026531840 0               0         0x0000 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) __ip_local_out
0xffff00001603cae8 1   <empty>:0        4026531840 0               0         0x0800 1500  60    10.0.2.15:54448->1.1.1.1:80(tcp) nf_hook_slow
```

## [Cilium Service Mesh](https://docs.cilium.io/en/stable/network/servicemesh/)
- L3/L4(ip, tcp, dup) 수준 프로토콜은 eBPF 처리
- L7(http, kafak, grpc, dns) 수준 애플리케이션 cilium-envoy 처리

샘플 애플리케이션 배포
```sh
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
```

## [k8s Ingress](https://docs.cilium.io/en/stable/network/servicemesh/ingress/)

Ingres 설정
```sh
# ingerss 설정 조회
cilium config view | grep -E '^loadbalancer|l7'
enable-l7-proxy                                   true
loadbalancer-l7                                   envoy
loadbalancer-l7-algorithm                         round_robin
loadbalancer-l7-ports

# ingress으로 예약된 ip 조회
k exec -it -n kube-system ds/cilium -- cilium ip list | grep ingress
172.20.0.85/32      reserved:ingress
172.20.1.188/32     reserved:ingress

# envoy 파드 조회
k get pod -n kube-system -l k8s-app=cilium-envoy -owide
NAME                 READY   STATUS    RESTARTS   AGE   IP               NODE      NOMINATED NODE   READINESS GATES
cilium-envoy-dv978   1/1     Running   0          10h   192.168.10.100   k8s-ctr   <none>           <none>
cilium-envoy-lvzxw   1/1     Running   0          10h   192.168.10.101   k8s-w1    <none>           <none>

# envoy는 호스트 포트 9964를 사용하며 소켓을 마운트하여 동작한다.
kc describe pod -n kube-system -l k8s-app=cilium-envoy
    Port:          9964/TCP
    Host Port:     9964/TCP
    Command:
      /usr/bin/cilium-envoy-starter
    Args:
      --
      -c /var/run/cilium/envoy/bootstrap-config.json
      --base-id 0
      --log-level info
    Mounts:
      /sys/fs/bpf from bpf-maps (rw)
      /var/run/cilium/envoy/ from envoy-config (ro)
      /var/run/cilium/envoy/artifacts from envoy-artifacts (ro)
      /var/run/cilium/envoy/sockets from envoy-sockets (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-8cjjr (ro)
Volumes:
  envoy-sockets:
    Type:          HostPath (bare host directory volume)
    Path:          /var/run/cilium/envoy/sockets
    HostPathType:  DirectoryOrCreate
  envoy-artifacts:
    Type:          HostPath (bare host directory volume)
    Path:          /var/run/cilium/envoy/artifacts
    HostPathType:  DirectoryOrCreate
  envoy-config:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      cilium-envoy-config
    Optional:  false
  bpf-maps:
    Type:          HostPath (bare host directory volume)
    Path:          /sys/fs/bpf
    HostPathType:  DirectoryOrCreate
  kube-api-access-8cjjr:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    Optional:                false
    DownwardAPI:             true

# 노드의 envoy 소켓 조회
ls -al /var/run/cilium/envoy/sockets
total 0
drwxr-xr-x 3 root root 120 Aug 23 13:00 .
drwxr-xr-x 4 root root  80 Aug 23 12:59 ..
srw-rw---- 1 root 1337   0 Aug 23 13:00 access_log.sock
srwxr-xr-x 1 root root   0 Aug 23 13:00 admin.sock
drwxr-xr-x 3 root root  60 Aug 23 13:00 envoy
srw-rw---- 1 root 1337   0 Aug 23 13:00 xds.sock

k exec -it -n kube-system ds/cilium-envoy -- ls -al /var/run/cilium/envoy
total 12
drwxrwxrwx 5 root root 4096 Aug 23 03:59 .
drwxr-xr-x 3 root root 4096 Aug 23 04:00 ..
drwxr-xr-x 2 root root 4096 Aug 23 03:59 ..2025_08_23_03_59_39.963203549
lrwxrwxrwx 1 root root   31 Aug 23 03:59 ..data -> ..2025_08_23_03_59_39.963203549
drwxr-xr-x 2 root root   40 Aug 23 03:59 artifacts
lrwxrwxrwx 1 root root   28 Aug 23 03:59 bootstrap-config.json -> ..data/bootstrap-config.json
drwxr-xr-x 3 root root  120 Aug 23 04:00 sockets

# envoy boostrap 설정 조회
k exec -it -n kube-system ds/cilium-envoy -- cat /var/run/cilium/envoy/bootstrap-config.json > envoy.json
cat envoy.json | jq

# envoy cm 조회
k -n kube-system get configmap cilium-envoy-config
NAME                  DATA   AGE
cilium-envoy-config   1      11h

# envoy boostrap 확인
k -n kube-system get configmap cilium-envoy-config -o json \
  | jq -r '.data["bootstrap-config.json"]' \
  | jq .

# ebpf에 마운트된 요소 조회
tree /sys/fs/bpf
/sys/fs/bpf
├── cilium
│   ├── devices
│   │   ├── cilium_host
│   │   │   └── links
│   │   │       ├── cil_from_host
│   │   │       └── cil_to_host
│   │   ├── cilium_net
│   │   │   └── links
│   │   │       └── cil_to_host
│   │   ├── eth0
│   │   │   └── links
│   │   │       ├── cil_from_netdev
│   │   │       └── cil_to_netdev
│   │   └── eth1
│   │       └── links
│   │           ├── cil_from_netdev
│   │           └── cil_to_netdev

# envoy 조회
k get svc,ep -n kube-system cilium-envoy
NAME                   TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/cilium-envoy   ClusterIP   None         <none>        9964/TCP   11h
NAME                     ENDPOINTS                                 AGE
endpoints/cilium-envoy   192.168.10.100:9964,192.168.10.101:9964   11h

# cilium-ingress 조회
k get svc,ep -n kube-system cilium-ingress
NAME                     TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)                      AGE
service/cilium-ingress   LoadBalancer   10.96.83.82   <pending>     80:31821/TCP,443:30271/TCP   11h
NAME                       ENDPOINTS              AGE
endpoints/cilium-ingress   192.192.192.192:9999   11h
```

L2 배포 
```sh
# L2 Announcement 설정 조회
cilium config view | grep l2
enable-l2-announcements                           true
enable-l2-neigh-discovery                         false

# L2 ip 대역 배포
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2" 
kind: CiliumLoadBalancerIPPool
metadata:
  name: "cilium-lb-ippool"
spec:
  blocks:
  - start: "192.168.10.211"
    stop:  "192.168.10.215"
EOF

k get ciliumloadbalancerippools.cilium.io
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cilium-lb-ippool   false      False         4               27s

# 5개의 ip 중 한개 사용. 앞서 생성한 인그레스가 할당받았다.
k get ippools -o jsonpath='{.items[*].status.conditions[?(@.type!="cilium.io/PoolConflict")]}' | jq
{
  "lastTransitionTime": "2025-08-23T15:07:24Z",
  "message": "5",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsTotal"
}
{
  "lastTransitionTime": "2025-08-23T15:07:24Z",
  "message": "4",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsAvailable"
}
{
  "lastTransitionTime": "2025-08-23T15:07:24Z",
  "message": "1",
  "observedGeneration": 1,
  "reason": "noreason",
  "status": "Unknown",
  "type": "cilium.io/IPsUsed"
}

# L2 Announcement 정책 설정
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: policy1
spec:
  interfaces:
  - eth1
  externalIPs: true
  loadBalancerIPs: true
EOF

# Announce 노드 조회
k -n kube-system get lease | grep "cilium-l2announce"
cilium-l2announce-kube-system-cilium-ingress   k8s-w1                                                                      17s

k -n kube-system get lease/cilium-l2announce-kube-system-cilium-ingress -o yaml | yq
{
  "apiVersion": "coordination.k8s.io/v1",
  "kind": "Lease",
  "metadata": {
    "creationTimestamp": "2025-08-23T15:09:11Z",
    "name": "cilium-l2announce-kube-system-cilium-ingress",
    "namespace": "kube-system",
    "resourceVersion": "6371",
    "uid": "f2d537e6-1f32-41f4-853f-6aa1407c2707"
  },
  "spec": {
    "acquireTime": "2025-08-23T15:09:11.098735Z",
    "holderIdentity": "k8s-w1",
    "leaseDurationSeconds": 15,
    "leaseTransitions": 0,
    "renewTime": "2025-08-23T15:09:55.243473Z"
  }
}

# LB ip 조회
LBIP=$(kubectl get svc -n kube-system cilium-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $LBIP
192.168.10.211

arping -i eth1 $LBIP -c 2
ARPING 192.168.10.211
60 bytes from 08:00:27:b3:c9:53 (192.168.10.211): index=0 time=670.919 usec
60 bytes from 08:00:27:b3:c9:53 (192.168.10.211): index=1 time=403.243 usec

# k8s 외부에서 LB-IP에 응답하는지 확인
sshpass -p 'vagrant' ssh vagrant@router sudo arping -i eth1 $LBIP -c 2
60 bytes from 08:00:27:b3:c9:53 (192.168.10.211): index=0 time=604.094 usec
60 bytes from 08:00:27:b3:c9:53 (192.168.10.211): index=1 time=322.494 usec
```

Ingress HTTP 샘플 [애플리케이션 배포](https://docs.cilium.io/en/stable/network/servicemesh/http/)
```sh
k apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/bookinfo/platform/kube/bookinfo.yaml

# istio와 다르게 모든 파드가 1개의 컨테이너만을 가진다
k get pod,svc,ep
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                                  READY   STATUS    RESTARTS   AGE
pod/curl-pod                          1/1     Running   0          9h
pod/details-v1-766844796b-nx4qj       1/1     Running   0          58s
pod/productpage-v1-54bb874995-w5bgh   1/1     Running   0          58s
pod/ratings-v1-5dc79b6bcd-xm6hv       1/1     Running   0          58s
pod/reviews-v1-598b896c9d-kgq7r       1/1     Running   0          58s
pod/reviews-v2-556d6457d-gm47q        1/1     Running   0          58s
pod/reviews-v3-564544b4d6-gmcrc       1/1     Running   0          58s
pod/webpod-697b545f57-9g222           1/1     Running   0          9h
pod/webpod-697b545f57-vtzft           1/1     Running   0          9h

NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/details       ClusterIP   10.96.232.98    <none>        9080/TCP   58s
service/kubernetes    ClusterIP   10.96.0.1       <none>        443/TCP    11h
service/productpage   ClusterIP   10.96.134.241   <none>        9080/TCP   58s
service/ratings       ClusterIP   10.96.176.211   <none>        9080/TCP   58s
service/reviews       ClusterIP   10.96.129.237   <none>        9080/TCP   58s
service/webpod        ClusterIP   10.96.125.129   <none>        80/TCP     9h

NAME                    ENDPOINTS                                              AGE
endpoints/details       172.20.1.169:9080                                      58s
endpoints/kubernetes    192.168.10.100:6443                                    11h
endpoints/productpage   172.20.1.116:9080                                      58s
endpoints/ratings       172.20.1.18:9080                                       58s
endpoints/reviews       172.20.1.155:9080,172.20.1.218:9080,172.20.1.83:9080   58s
endpoints/webpod        172.20.0.181:80,172.20.1.211:80                        9h

kc describe ingressclasses.networking.k8s.io
Name:         cilium
Labels:       app.kubernetes.io/managed-by=Helm
Annotations:  meta.helm.sh/release-name: cilium
              meta.helm.sh/release-namespace: kube-system
Controller:   cilium.io/ingress-controller
Events:       <none>

k get ingressclasses.networking.k8s.io
NAME     CONTROLLER                     PARAMETERS   AGE
cilium   cilium.io/ingress-controller   <none>       11h

# 인그레스 배포 
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: basic-ingress
  namespace: default
spec:
  ingressClassName: cilium
  rules:
  - http:
      paths:
      - backend:
          service:
            name: details
            port:
              number: 9080
        path: /details
        pathType: Prefix
      - backend:
          service:
            name: productpage
            port:
              number: 9080
        path: /
        pathType: Prefix
EOF

# 인그레스는 211 ip로 통신한다.
k get svc -n kube-system cilium-ingress
NAME             TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)                      AGE
cilium-ingress   LoadBalancer   10.96.83.82   192.168.10.211   80:31821/TCP,443:30271/TCP   11h

k get ingress
NAME            CLASS    HOSTS   ADDRESS          PORTS   AGE
basic-ingress   cilium   *       192.168.10.211   80      48s

# 인그레스에 대한 설정
kc describe ingress
Name:             basic-ingress
Labels:           <none>
Namespace:        default
Address:          192.168.10.211
Ingress Class:    cilium
Default backend:  <default>
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /details   details:9080 (172.20.1.169:9080)
              /          productpage:9080 (172.20.1.116:9080)
Annotations:  <none>
Events:       <none>

LBIP=$(kubectl get svc -n kube-system cilium-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $LBIP
192.168.10.211 

# 호출 조회
curl -so /dev/null -w "%{http_code}\n" http://$LBIP/
200

curl -so /dev/null -w "%{http_code}\n" http://$LBIP/details/1
200

curl -so /dev/null -w "%{http_code}\n" http://$LBIP/ratings
404

# html으로 응답한다
curl "http://$LBIP/productpage?u=normal"

# 허블 모니터링
cilium hubble port-forward&
hubble observe -f -t l7
Aug 23 15:19:00.003: 192.168.10.200:59022 (ingress) -> default/productpage-v1-54bb874995-w5bgh:9080 (ID:32530) http-request FORWARDED (HTTP/1.1 GET http://192.168.10.211/)
Aug 23 15:19:00.006: 192.168.10.200:59022 (ingress) <- default/productpage-v1-54bb874995-w5bgh:9080 (ID:32530) http-response FORWARDED (HTTP/1.1 200 7ms (GET http://192.168.10.211/))
Aug 23 15:19:26.911: 192.168.10.200:50104 (ingress) -> default/details-v1-766844796b-nx4qj:9080 (ID:3123) http-request FORWARDED (HTTP/1.1 GET http://192.168.10.211/details/1)
Aug 23 15:19:26.913: 192.168.10.200:50104 (ingress) <- default/details-v1-766844796b-nx4qj:9080 (ID:3123) http-response FORWARDED (HTTP/1.1 200 3ms (GET http://192.168.10.211/details/1))


# 라우터 서버
LBIP=192.168.10.211
curl -so /dev/null -w "%{http_code}\n" http://$LBIP/
200
curl -so /dev/null -w "%{http_code}\n" http://$LBIP/details/1
200

# http 요청이기 때문에 envoy가 처리한다.
curl -s http://$LBIP/details/1 -v
*   Trying 192.168.10.211:80...
* Connected to 192.168.10.211 (192.168.10.211) port 80
> GET /details/1 HTTP/1.1
> Host: 192.168.10.211
> User-Agent: curl/8.5.0
> Accept: */*
>
< HTTP/1.1 200 OK
< content-type: application/json
< server: envoy
< date: Sat, 23 Aug 2025 15:20:18 GMT
< content-length: 178
< x-envoy-upstream-service-time: 2

k get pod -l app=productpage -owide
NAME                              READY   STATUS    RESTARTS   AGE    IP             NODE     NOMINATED NODE   READINESS GATES
productpage-v1-54bb874995-w5bgh   1/1     Running   0          8m3s   172.20.1.116   k8s-w1   <none>           <none>

# k8s-w1
PODIP=172.20.1.116

ip route |grep $PODIP
172.20.1.116 dev lxc2708e37270fc proto kernel scope link

# ngrep으로 veth 패킷 캡처
PROVETH=lxc2708e37270fc
ngrep -tW byline -d $PROVETH '' 'tcp port 9080'

# 요청 테스트 
sshpass -p 'vagrant' ssh vagrant@router curl -s http://$LBIP

# 응답 확인 
lxc2708e37270fc: no IPv4 address assigned: Cannot assign requested address
interface: lxc2708e37270fc
filter: ( tcp port 9080 ) and ((ip || ip6) || (vlan && (ip || ip6)))

# x-forwarded-for로 요청을 보낸 소스 ip가 조회된다.
T 2025/08/24 00:24:38.646692 10.0.2.15:38014 -> 172.20.1.116:9080 [AP] #4
GET / HTTP/1.1.
host: 192.168.10.211.
user-agent: curl/8.5.0.
accept: */*.
x-forwarded-for: 192.168.10.200.
x-forwarded-proto: http.
x-envoy-internal: true.
x-request-id: 9f80d673-a6b0-476d-927c-7d59edeaf485.

# 해당 요청에 대한 envoy의 응답 
T 2025/08/24 00:24:38.647498 172.20.1.116:9080 -> 10.0.2.15:38014 [AP] #6
HTTP/1.1 200 OK.
Server: gunicorn.
Date: Sat, 23 Aug 2025 15:24:38 GMT.
Connection: keep-alive.
Content-Type: text/html; charset=utf-8.
Content-Length: 2080.
```


Nginx-ingress와 cilium-ingress 동시 설정 
```sh
# Ingress-Nginx 배포
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace -n ingress-nginx

# nginx 리소스 조회
k get all -n ingress-nginx
kc describe svc -n ingress-nginx ingress-nginx-controller

k get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.96.38.204    192.168.10.212   80:31180/TCP,443:31090/TCP   59s
ingress-nginx-controller-admission   ClusterIP      10.96.209.161   <none>           443/TCP                      59s

# 2개의 인그레스 컨트롤러가 존재한다.
k get ingressclasses.networking.k8s.io
NAME     CONTROLLER                     PARAMETERS   AGE
cilium   cilium.io/ingress-controller   <none>       11h
nginx    k8s.io/ingress-nginx           <none>       26s

# ingerss nginx 배포
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webpod-ingress-nginx
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.webpod.local
    http:
      paths:
      - backend:
          service:
            name: webpod
            port:
              number: 80
        path: /
        pathType: Prefix
EOF

k get ingress -w
webpod-ingress-nginx   nginx    nginx.webpod.local   192.168.10.212   80      16s

LB2IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 호스트가 없기 때문에 404 
curl $LB2IP
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>

# nginx가 해당 요청에 응답한 것을 볼수 있다.
curl -H "Host: nginx.webpod.local" $LB2IP
Hostname: webpod-697b545f57-9g222
IP: 127.0.0.1
IP: ::1
IP: 172.20.0.181
IP: fe80::382a:faff:fe95:1855
RemoteAddr: 172.20.1.29:46244
GET / HTTP/1.1
Host: nginx.webpod.local
User-Agent: curl/8.5.0
Accept: */*
X-Forwarded-For: 192.168.10.100
X-Forwarded-Host: nginx.webpod.local
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Scheme: http
X-Real-Ip: 192.168.10.100
X-Request-Id: 57beccebae53566322140f70e36746de
X-Scheme: http

# 라우터에서도 잘 응답한다.
sshpass -p 'vagrant' ssh vagrant@router "curl -s -H 'Host: nginx.webpod.local' $LB2IP"
Hostname: webpod-697b545f57-vtzft
IP: 127.0.0.1
IP: ::1
IP: 172.20.1.211
IP: fe80::41e:5dff:feb3:a441
RemoteAddr: 172.20.1.29:44400
GET / HTTP/1.1
Host: nginx.webpod.local
User-Agent: curl/8.5.0
Accept: */*
X-Forwarded-For: 192.168.10.100
X-Forwarded-Host: nginx.webpod.local
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Scheme: http
X-Real-Ip: 192.168.10.100
X-Request-Id: 51a55fed6b7db8eb8115bf71fa9a1aea
X-Scheme: http
```

ciliun-ingess dedicated mode
```sh
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webpod-ingress
  namespace: default
  annotations:
    ingress.cilium.io/loadbalancer-mode: dedicated
spec:
  ingressClassName: cilium
  rules:
  - http:
      paths:
      - backend:
          service:
            name: webpod
            port:
              number: 80
        path: /
        pathType: Prefix
EOF

# ingress 설정 조횐
kc describe ingress webpod-ingress
Name:             webpod-ingress
Labels:           <none>
Namespace:        default
Address:          192.168.10.213
Ingress Class:    cilium
Default backend:  <default>
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /   webpod:80 (172.20.1.211:80,172.20.0.181:80)
Annotations:  ingress.cilium.io/loadbalancer-mode: dedicated
Events:       <none>

# 또 다른 ingress가 생성되었다.
k get ingress
NAME                   CLASS    HOSTS                ADDRESS          PORTS   AGE
basic-ingress          cilium   *                    192.168.10.211   80      18m
webpod-ingress         cilium   *                    192.168.10.213   80      100s
webpod-ingress-nginx   nginx    nginx.webpod.local   192.168.10.212   80      3m55s

k get svc,ep cilium-ingress-webpod-ingress
NAME                                    TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
service/cilium-ingress-webpod-ingress   LoadBalancer   10.96.144.57   192.168.10.213   80:31591/TCP,443:30868/TCP   111s
NAME                                      ENDPOINTS              AGE
endpoints/cilium-ingress-webpod-ingress   192.192.192.192:9999   111s

# l2 광고 노드 조회
k get lease -n kube-system | grep ingress
cilium-l2announce-default-cilium-ingress-webpod-ingress    k8s-ctr                                                                     2m9s
cilium-l2announce-ingress-nginx-ingress-nginx-controller   k8s-ctr                                                                     5m38s
cilium-l2announce-kube-system-cilium-ingress               k8s-w1                                                                      25m

k get pod -l app=webpod -owide
NAME                      READY   STATUS    RESTARTS   AGE   IP             NODE      NOMINATED NODE   READINESS GATES
webpod-697b545f57-9g222   1/1     Running   0          9h    172.20.0.181   k8s-ctr   <none>           <none>
webpod-697b545f57-vtzft   1/1     Running   0          9h    172.20.1.211   k8s-w1    <none>           <none>

# k8c-ctr, k8s-w1 노드에서 파드 IP에 veth 찾기(ip -c route) 이후 ngrep 로 각각 트래픽 캡쳐

# k8s-ctr
ip -c r | grep 172.20.0.181
WPODVETH=lxc3494ec9b7b8b
ngrep -tW byline -d $WPODVETH '' 'tcp port 80'

# k8s-w1
ip -c r | grep 172.20.1.211
WPODVETH=lxccdf001cf46e2
ngrep -tW byline -d $WPODVETH '' 'tcp port 80'

LB2IP=$(kubectl get svc cilium-ingress-webpod-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $LB2IP
LB2IP=192.168.10.213

# 라우터 호출 
sshpass -p 'vagrant' ssh vagrant@router curl -s http://$LB2IP
### 파드 1 응답
Hostname: webpod-697b545f57-9g222
IP: 127.0.0.1
IP: ::1
IP: 172.20.0.181 # web pod ip
IP: fe80::382a:faff:fe95:1855
RemoteAddr: 10.0.2.15:52324 # l2 리더 노드의 파드 ip가 조회된다. 소스 ip가 리더 노드의 첫 번째 nic ip이다. 
GET / HTTP/1.1.
Host: 192.168.10.213.
User-Agent: curl/8.5.0.
Accept: */*.
X-Envoy-Internal: true.
X-Forwarded-For: 192.168.10.200.
X-Forwarded-Proto: http.
X-Request-Id: 7a7bafff-36e9-461d-8d3a-6d3e4ebec8b4.

### 파드 2 응답
Hostname: webpod-697b545f57-vtzft
IP: 127.0.0.1
IP: ::1
IP: 172.20.1.211
IP: fe80::41e:5dff:feb3:a441
RemoteAddr: 172.20.0.85:44713 # webpod 인입 시 소스 ip로 L2 Leader 노드(k8s-w1)에서 다른 노드에 파드로 전달되어, ingress 예약IP로 SNAT. 글의 맨 처음 조회했던 예약 ip이다.
GET / HTTP/1.1. 
Host: 192.168.10.213.
User-Agent: curl/8.5.0.
Accept: */*.
X-Envoy-Internal: true.
X-Forwarded-For: 192.168.10.200.
X-Forwarded-Proto: http.
X-Request-Id: 8d817e9b-dbe3-48a6-9385-4131de954423.
```


ingress [network policy](https://docs.cilium.io/en/stable/network/servicemesh/ingress-and-network-policy/)
```sh
#클러스터 정책 설정 외부로 오는 모든 요청은 거절된다.
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "external-lockdown"
spec:
  description: "Block all the traffic originating from outside of the cluster"
  endpointSelector: {}
  ingress:
  - fromEntities:
    - cluster
EOF

k get ciliumclusterwidenetworkpolicy
NAME                VALID
external-lockdown   True

# router
# 접근이 안된다.
LBIP=192.168.10.211
curl --fail -v http://"$LBIP"/details/1
< HTTP/1.1 403 Forbidden

# k8s-ctr
hubble observe -f --identity ingress

# k8s-ctr 
# 요청이 드랍된다.
LBIP=192.168.10.211
curl --fail -v http://"$LBIP"/details/1
Aug 23 15:53:23.141: 127.0.0.1:39788 (ingress) -> 127.0.0.1:17873 (world) http-request DROPPED (HTTP/1.1 GET http://192.168.10.211/details/1)
Aug 23 15:53:23.141: 127.0.0.1:39788 (ingress) <- 127.0.0.1:17873 (world) http-response FORWARDED (HTTP/1.1 403 0ms (GET http://192.168.10.211/details/1))

# router
# 요청이 드랍된다. 
LBIP=192.168.10.211
curl --fail -v http://"$LBIP"/details/1
Aug 23 15:52:34.306: 192.168.10.200:49840 (ingress) -> kube-system/cilium-ingress:80 (world) http-request DROPPED (HTTP/1.1 GET http://192.168.10.211/details/1)
Aug 23 15:52:34.306: 192.168.10.200:49840 (ingress) <- kube-system/cilium-ingress:80 (world) http-response FORWARDED (HTTP/1.1 403 0ms (GET http://192.168.10.211/details/1))

# 예약된 인그레스 주소에 대해서, 해당하는 파드 ip에 대해서 요청을 허용한다.
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "allow-cidr"
spec:
  description: "Allow all the traffic originating from a specific CIDR"
  endpointSelector:
    matchExpressions:
    - key: reserved:ingress
      operator: Exists
  ingress:
  - fromCIDRSet:
    # Please update the CIDR to match your environment
    - cidr: 192.168.10.200/32
    - cidr: 127.0.0.1/32
EOF


# k8s-ctr, k8s-w1, router 모두 응답한다.
curl --fail -v http://"$LBIP"/details/1
sshpass -p 'vagrant' ssh vagrant@router "curl -s --fail -v http://"$LBIP"/details/1"
< HTTP/1.1 200 OK

# dns 쿼리 및 kube-system 내의 파드 제외 모든 트래픽 거부
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "default-deny"
spec:
  description: "Block all the traffic (except DNS) by default"
  egress:
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: '53'
        protocol: UDP
      rules:
        dns:
        - matchPattern: '*'
  endpointSelector:
    matchExpressions:
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system
EOF
k get ciliumclusterwidenetworkpolicy
NAME                VALID
allow-cidr          True
default-deny        True
external-lockdown   True


# http 요청 
curl --fail -v http://"$LBIP"/details/1
sshpass -p 'vagrant' ssh vagrant@router "curl -s --fail -v http://"$LBIP"/details/1"
< HTTP/1.1 403 Forbidden

# ingress를 통한 요청 허용
cat << EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-ingress-egress
spec:
  description: "Allow all the egress traffic from reserved ingress identity to any endpoints in the cluster"
  endpointSelector:
    matchExpressions:
    - key: reserved:ingress
      operator: Exists
  egress:
  - toEntities:
    - cluster
EOF

k get ciliumclusterwidenetworkpolicy
NAME                   VALID
allow-cidr             True
allow-ingress-egress   True
default-deny           True
external-lockdown      True

# 정상 응답
curl --fail -v http://"$LBIP"/details/1
sshpass -p 'vagrant' ssh vagrant@router "curl -s --fail -v http://"$LBIP"/details/1"
< HTTP/1.1 200 OK

# 정책 삭제
k delete CiliumClusterwideNetworkPolicy --all
```

Ingress [Path Type](https://docs.cilium.io/en/stable/network/servicemesh/path-types/)
```sh
# 샘플 애플리케이션 배포
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types.yaml

# 리소스 조회
kubectl get -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types.yaml
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/exactpath     1/1     1            1           16s
deployment.apps/prefixpath    1/1     1            1           16s
deployment.apps/prefixpath2   1/1     1            1           16s
deployment.apps/implpath      1/1     1            1           16s
deployment.apps/implpath2     1/1     1            1           16s

NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/prefixpath    ClusterIP   10.96.163.162   <none>        80/TCP    16s
service/prefixpath2   ClusterIP   10.96.138.214   <none>        80/TCP    16s
service/exactpath     ClusterIP   10.96.204.126   <none>        80/TCP    16s
service/implpath      ClusterIP   10.96.197.138   <none>        80/TCP    16s
service/implpath2     ClusterIP   10.96.144.144   <none>        80/TCP    16s

# 인그레스 배포
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types-ingress.yaml

kc describe ingress multiple-path-types
kc get ingress multiple-path-types -o yaml

export PATHTYPE_IP=`k get ing multiple-path-types -o json | jq -r '.status.loadBalancer.ingress[0].ip'`
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/ | jq
kubectl get pod | grep path

curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/ | grep -E 'path|pod'
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/exact | grep -E 'path|pod'

curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/prefix | grep -E 'path|pod'
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/impl | grep -E 'path|pod'
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/implementation | grep -E 'path|pod'

```bash
# Apply the base definitions
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types.yaml

# 확인
kubectl get -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types.yaml

# Apply the Ingress
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types-ingress.yaml

# 확인
# 다양한 경로에 따른 설정 확
kc describe ingress multiple-path-types
Name:             multiple-path-types
Labels:           <none>
Namespace:        default
Address:          192.168.10.211
Ingress Class:    cilium
Default backend:  <default>
Rules:
  Host                   Path  Backends
  ----                   ----  --------
  pathtypes.example.com
                         /exact    exactpath:80 (172.20.1.199:3000)
                         /         prefixpath:80 (172.20.1.198:3000)
                         /prefix   prefixpath2:80 (172.20.1.19:3000)
                         /impl     implpath:80 (172.20.1.157:3000)
                         /impl.+   implpath2:80 (172.20.1.121:3000)
Annotations:             <none>
Events:                  <none>

# 인그레스 룰 조회
kc get ingress multiple-path-types -o yaml
spec:
  ingressClassName: cilium
  rules:
  - host: pathtypes.example.com
    http:
      paths:
      - backend:
          service:
            name: exactpath
            port:
              number: 80
        path: /exact
        pathType: Exact
      - backend:
          service:
            name: prefixpath
            port:
              number: 80
        path: /
        pathType: Prefix
      - backend:
          service:
            name: prefixpath2
            port:
              number: 80
        path: /prefix
        pathType: Prefix
      - backend:
          service:
            name: implpath
            port:
              number: 80
        path: /impl
        pathType: ImplementationSpecific
      - backend:
          service:
            name: implpath2
            port:
              number: 80
        path: /impl.+
        pathType: ImplementationSpecific

# 호출 확인
export PATHTYPE_IP=`k get ing multiple-path-types -o json | jq -r '.status.loadBalancer.ingress[0].ip'`

# 기본 경로인 파드가 응답한다.
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/ | jq
"host": "pathtypes.example.com",


# 파드명 이름 확인
kubectl get pod | grep path
exactpath-7488f8c6c6-b6xsj        1/1     Running   0          3m59s
implpath-7d8bf85676-smj4q         1/1     Running   0          3m59s
implpath2-56c97c8556-rm466        1/1     Running   0          3m59s
prefixpath-5d6b989d4-m26jh        1/1     Running   0          3m59s
prefixpath2-b7c7c9568-64w2n       1/1     Running   0          3m59s

# 기본 경로 응답 조회
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/ | grep -E 'path|pod'
 "path": "/",
 "host": "pathtypes.example.com",
 "pod": "prefixpath-5d6b989d4-m26jh"

# exact에 일치하는 파드 응답 조회
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/exact | grep -E 'path|pod'
 "path": "/exact",
 "host": "pathtypes.example.com",
 "pod": "exactpath-7488f8c6c6-b6xsj"

# prefix에 일치하는 파드 응답 조회
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/prefix | grep -E 'path|pod'
 "path": "/prefix",
 "host": "pathtypes.example.com",
 "pod": "prefixpath2-b7c7c9568-64w2n"

# 구현체에 일치하는 파드 응답 조회
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/impl | grep -E 'path|pod'
 "path": "/impl",
 "host": "pathtypes.example.com",
 "pod": "implpath-7d8bf85676-smj4q"

# 정규표현식에 일치하는 파드 조회
curl -s -H "Host: pathtypes.example.com" http://$PATHTYPE_IP/implementation | grep -E 'path|pod'
 "path": "/implementation",
 "host": "pathtypes.example.com",
 "pod": "implpath2-56c97c8556-rm466"

# 리소스 삭제 
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types.yaml
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/main/examples/kubernetes/servicemesh/ingress-path-types-ingress.yaml
```

Igress Example with [TLS Termination](https://docs.cilium.io/en/stable/network/servicemesh/tls-termination/)

```sh
# 내가 사용할 도메인에 대한 tls 생성 도구
apt install mkcert -y
mkcert -h

# 로컬 ca에 신뢰할수 있는 인증서에는 등록되지 않은 상태이다.
mkcert '*.cilium.rocks'
Created a new local CA 💥
Note: the local CA is not installed in the system trust store.
Run "mkcert -install" for certificates to be trusted automatically ⚠️
Created a new certificate valid for the following names 📜
 - "*.cilium.rocks"
Reminder: X.509 wildcards only go one level deep, so this won't match a.b.cilium.rocks ℹ️
The certificate is at "./_wildcard.cilium.rocks.pem" and the key at "./_wildcard.cilium.rocks-key.pem" ✅
It will expire on 24 November 2027 🗓'

# 인증서 목록 조회
ls -l *.pem
-rw------- 1 root root 1704 Aug 24 01:19 _wildcard.cilium.rocks-key.pem
-rw-r--r-- 1 root root 1452 Aug 24 01:19 _wildcard.cilium.rocks.pem

# 인증서 조회
openssl x509 -in _wildcard.cilium.rocks.pem -text -noout

# 프라이빗키 조회
openssl rsa -in _wildcard.cilium.rocks-key.pem -text -noout

# 시크릿 생성
kubectl create secret tls demo-cert --key=_wildcard.cilium.rocks-key.pem --cert=_wildcard.cilium.rocks.pem

# 시크릿 상태 조회
kubectl get secret demo-cert -o json | jq
...
  "kind": "Secret",
  "metadata": {
    "creationTimestamp": "2025-08-23T16:23:13Z",
    "name": "demo-cert",
    "namespace": "default",
    "resourceVersion": "21028",
    "uid": "ddcfcd49-7f71-4236-bb72-37c1a0468f4c"
  },
  "type": "kubernetes.io/tls"
}

# 인그레스 배포
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  namespace: default
spec:
  ingressClassName: cilium
  rules:
  - host: webpod.cilium.rocks
    http:
      paths:
      - backend:
          service:
            name: webpod
            port:
              number: 80
        path: /
        pathType: Prefix
  - host: bookinfo.cilium.rocks
    http:
      paths:
      - backend:
          service:
            name: details
            port:
              number: 9080
        path: /details
        pathType: Prefix
      - backend:
          service:
            name: productpage
            port:
              number: 9080
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - webpod.cilium.rocks
    - bookinfo.cilium.rocks
    secretName: demo-cert
EOF

# 인그레스 상태 조회
k get ingress tls-ingress
NAME          CLASS    HOSTS                                       ADDRESS          PORTS     AGE
tls-ingress   cilium   webpod.cilium.rocks,bookinfo.cilium.rocks   192.168.10.211   80, 443   8s

# 신뢰할수 있는 인증서 조회
ls -al /etc/ssl/certs/ca-certificates.crt

# mkcrt 위치 조회
mkcert -CAROOT

# 내 로컬에서 만든 인증서를 시스템이 신뢰할수 있도록 한다.
mkcert -install
The local CA is now installed in the system trust store! ⚡️kubectl get ingress tls-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# LBIP 획득 후 조회
k get ingress tls-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
LBIP=$(kubectl get ingress tls-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -s --resolve bookinfo.cilium.rocks:443:${LBIP} https://bookinfo.cilium.rocks/details/1 | jq
{
  "id": 1,
  "author": "William Shakespeare",
  "year": 1595,
  "type": "paperback",
  "pages": 200,
  "publisher": "PublisherA",
  "language": "English",
  "ISBN-10": "1234567890",
  "ISBN-13": "123-1234567890"
}

curl -s --resolve webpod.cilium.rocks:443:${LBIP}   https://webpod.cilium.rocks/ -v
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
...
* Server certificate:
*  subject: O=mkcert development certificate; OU=root@k8s-ctr
*  start date: Aug 23 16:19:46 2025 GMT
*  expire date: Nov 23 16:19:46 2027 GMT
*  subjectAltName: host "webpod.cilium.rocks" matched cert's "*.cilium.rocks"
*  issuer: O=mkcert development CA; OU=root@k8s-ctr; CN=mkcert root@k8s-ctr
*  SSL certificate verify ok.
*   Certificate level 0: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type RSA (3072/128 Bits/secBits), signed using sha256WithRSAEncryption  '
```

## k8s [Gateway API](https://gateway-api.sigs.k8s.io/)
```sh
# ingress 리소스 삭제 
# gateay api와 동시 활성화가 안된다.
k delete ingress basic-ingress tls-ingress webpod-ingress

# crd 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

# crd 조횐
kubectl get crd | grep gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io     2025-08-23T16:40:17Z
gateways.gateway.networking.k8s.io           2025-08-23T16:40:18Z
grpcroutes.gateway.networking.k8s.io         2025-08-23T16:40:19Z
httproutes.gateway.networking.k8s.io         2025-08-23T16:40:18Z
referencegrants.gateway.networking.k8s.io    2025-08-23T16:40:19Z
tlsroutes.gateway.networking.k8s.io          2025-08-23T16:40:20Z

# cilium 배포
helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
--set ingressController.enabled=false --set gatewayAPI.enabled=true

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium

# cilium 설정 조회
cilium config view | grep gateway-api
enable-gateway-api                                true
enable-gateway-api-alpn                           false
enable-gateway-api-app-protocol                   false
enable-gateway-api-proxy-protocol                 false
enable-gateway-api-secrets-sync                   true
gateway-api-hostnetwork-enabled                   false
gateway-api-hostnetwork-nodelabelselector
gateway-api-secrets-namespace                     cilium-secrets
gateway-api-service-externaltrafficpolicy         Cluster
gateway-api-xff-num-trusted-hops                  0

# cilium-ingress 삭제 조회
k get svc,pod -n kube-system

# gateway 리소스 조회
k get GatewayClass
cilium   io.cilium/gateway-controller   True       105s

k get gateway -A

# gateway 배포
cat << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: cilium
  listeners:
  - protocol: HTTP
    port: 80
    name: web-gw
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-app-1
spec:
  parentRefs:
  - name: my-gateway
    namespace: default
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /details
    backendRefs:
    - name: details
      port: 9080
  - matches:
    - headers:
      - type: Exact
        name: magic
        value: foo
      queryParams:
      - type: Exact
        name: great
        value: example
      path:
        type: PathPrefix
        value: /
      method: GET
    backendRefs:
    - name: productpage
      port: 9080
EOF

# gateway 리소스 조회
k get svc,ep cilium-gateway-my-gateway
Slice
NAME                                TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)        AGE
service/cilium-gateway-my-gateway   LoadBalancer   10.96.17.97   192.168.10.211   80:32006/TCP   6s
NAME                                  ENDPOINTS              AGE
endpoints/cilium-gateway-my-gateway   192.192.192.192:9999   6s

# 동일한 ip를 할당받은 것을 볼수 있따.
k get gateway
NAME         CLASS    ADDRESS          PROGRAMMED   AGE
my-gateway   cilium   192.168.10.211   True         33s

kc describe gateway

# gateay - httproute 조회
k get httproutes -A
NAMESPACE   NAME         HOSTNAMES   AGE
default     http-app-1               8m12s

kc describe httproutes

# 오퍼레이터 로그 조회
kubectl logs -n kube-system deployments/cilium-operator | grep gateway

# IP 조회
GATEWAY=$(kubectl get gateway my-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY

# 응답 확인
curl --fail -s http://"$GATEWAY"/details/1 | jq
sshpass -p 'vagrant' ssh vagrant@router "curl -s --fail -v http://"$GATEWAY"/details/1"
{"id":1,"author":"William Shakespeare","year":1595,"type":"paperback","pages":200,"publisher":"PublisherA","language":"English","ISBN-10":"1234567890","ISBN-13":"123-1234567890"}< HTTP/1.1 200 OK

# 헤더를 가진 경우에 대한응답 확인
# 앞선 httproute의 정의에 맞게 다양한 형태의 헤더 설정도 가능하다.
curl -v -H 'magic: foo' http://"$GATEWAY"\?great\=example

# https 라우트 배포 
cat << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tls-gateway
spec:
  gatewayClassName: cilium
  listeners:
  - name: https-1
    protocol: HTTPS
    port: 443
    hostname: "bookinfo.cilium.rocks"
    tls:
      certificateRefs:
      - kind: Secret
        name: demo-cert
  - name: https-2
    protocol: HTTPS
    port: 443
    hostname: "webpod.cilium.rocks"
    tls:
      certificateRefs:
      - kind: Secret
        name: demo-cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-app-route-1
spec:
  parentRefs:
  - name: tls-gateway
  hostnames:
  - "bookinfo.cilium.rocks"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /details
    backendRefs:
    - name: details
      port: 9080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-app-route-2
spec:
  parentRefs:
  - name: tls-gateway
  hostnames:
  - "webpod.cilium.rocks"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: webpod
      port: 80
EOF

# tls가 적용된 gw 조회
k get gateway tls-gateway
NAME          CLASS    ADDRESS          PROGRAMMED   AGE
tls-gateway   cilium   192.168.10.213   True         9s

k get httproutes https-app-route-1 https-app-route-2
NAME                HOSTNAMES                   AGE
https-app-route-1   ["bookinfo.cilium.rocks"]   32s
https-app-route-2   ["webpod.cilium.rocks"]     32s

# LB 조회
GATEWAY2=$(kubectl get gateway tls-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY2
192.168.10.213

# 요청 
curl -s --resolve bookinfo.cilium.rocks:443:${GATEWAY2} https://bookinfo.cilium.rocks/details/1 | jq
{
  "id": 1,
  "author": "William Shakespeare",
  "year": 1595,
  "type": "paperback",
  "pages": 200,
  "publisher": "PublisherA",
  "language": "English",
  "ISBN-10": "1234567890",
  "ISBN-13": "123-1234567890"
}
# 요청 
curl -s --resolve webpod.cilium.rocks:443:${GATEWAY2}   https://webpod.cilium.rocks/ -v
```

TLS Route
Terminate는 외부 요청은 https로 동작. 내부간의 요청은 http로 평문 통신한다. 반면에 Passthrough은 모든 통신이 https로 통신한다. 이를 위해서는 파드에서도 tls 설정이 되어있어야 한다.
- In Terminate
    - Client → Gateway: HTTPS
    - Gateway → Pod: HTTP
- In Passthrough
    - Client → Gateway: HTTPS
    - Gateway → Pod: HTTPS

```sh
# HTTPS가 적용된 nginx 웹서버 설정
cat <<'EOF' > nginx.conf
events {
}

http {
  log_format main '$remote_addr - $remote_user [$time_local]  $status '
  '"$request" $body_bytes_sent "$http_referer" '
  '"$http_user_agent" "$http_x_forwarded_for"';
  access_log /var/log/nginx/access.log main;
  error_log  /var/log/nginx/error.log;

  server {
    listen 443 ssl;

    root /usr/share/nginx/html;
    index index.html;

    server_name nginx.cilium.rocks;
    ssl_certificate /etc/nginx-server-certs/tls.crt;
    ssl_certificate_key /etc/nginx-server-certs/tls.key;
  }
}
EOF

# cm 생성 
k create configmap nginx-configmap --from-file=nginx.conf=./nginx.conf

# https nginx 앱 배포
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  ports:
    - port: 443
      protocol: TCP
  selector:
    run: my-nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  selector:
    matchLabels:
      run: my-nginx
  replicas: 1
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
        - name: my-nginx
          image: nginx
          ports:
            - containerPort: 443
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx
              readOnly: true
            - name: nginx-server-certs
              mountPath: /etc/nginx-server-certs
              readOnly: true
      volumes:
        - name: nginx-config
          configMap:
            name: nginx-configmap
        - name: nginx-server-certs
          secret:
            secretName: demo-cert
EOF


k get deployment,svc,ep my-nginx
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-nginx   1/1     1            1           17s
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/my-nginx   ClusterIP   10.96.194.142   <none>        443/TCP   17s
NAME                 ENDPOINTS          AGE
endpoints/my-nginx   172.20.1.102:443   17s

# TLS Route 배포
# 중요한 것은 tls.mode에서 Passthrough을 설정해줘야 한다. v1alpha2으로 아직 개발단계이다.
cat << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cilium-tls-gateway
spec:
  gatewayClassName: cilium
  listeners:
    - name: https
      hostname: "nginx.cilium.rocks"
      port: 443
      protocol: TLS
      tls:
        mode: Passthrough
      allowedRoutes:
        namespaces:
          from: All
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: nginx
spec:
  parentRefs:
    - name: cilium-tls-gateway
  hostnames:
    - "nginx.cilium.rocks"
  rules:
    - backendRefs:
        - name: my-nginx
          port: 443
EOF

k get gateway cilium-tls-gateway
NAME                 CLASS    ADDRESS          PROGRAMMED   AGE
cilium-tls-gateway   cilium   192.168.10.214   True         42s

GATEWAY=$(kubectl get gateway cilium-tls-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
192.168.10.214

# TLS route 상태 조화
k get tlsroutes.gateway.networking.k8s.io -o json | jq '.items[0].status.parents[0]'
  "conditions": [
    {
      "lastTransitionTime": "2025-08-23T16:57:33Z",
      "message": "Accepted TLSRoute",
      "observedGeneration": 1,
      "reason": "Accepted",
      "status": "True",
      "type": "Accepted"
    },

k logs -l run=my-nginx -f 

# 웹 요청 
curl -v --resolve "nginx.cilium.rocks:443:$GATEWAY" "https://nginx.cilium.rocks:443"
172.20.0.85 - - [23/Aug/2025:17:03:32 +0000]  200 "GET / HTTP/1.1" 615 "-" "curl/8.5.0" "-"
```

Gateway [api address](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/#gateway-api-addresses-support)
```sh
# k9s -> gateway edit 
# gateway ip를 지정할수 있다.
spec:
  addresses:
  - type: IPAddress
    value: 192.168.10.215
  gatewayClassName: cilium
...

# 응답 테스트
GATEWAY=$(kubectl get gateway cilium-tls-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY

curl -v --resolve "nginx.cilium.rocks:443:$GATEWAY" "https://nginx.cilium.rocks:443"

# 리소스 제거
k delete gateway my-gateway tls-gateway cilium-tls-gateway
k delete -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/bookinfo/platform/kube/bookinfo.yaml
```


## [Mutual Authentication(beta](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/)
```sh
helm get values -n kube-system cilium > before.yaml
helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
    --set authentication.mutual.spire.enabled=true --set authentication.mutual.spire.install.enabled=true \
    --set authentication.mutual.spire.install.server.dataStorage.enabled=true 

k -n kube-system rollout restart deployment/cilium-operator
k -n kube-system rollout restart ds/cilium
k -n cilium-spire rollout restart sts spire-server

# 조회
k get all,svc,ep,configmap,secret,pvc -n cilium-spire

kc describe cm -n cilium-spire spire-server | grep socket_path
  socket_path = "/tmp/spire-server/private/api.sock"


cilium config view | grep mesh-auth
mesh-auth-enabled                                 true
mesh-auth-gc-interval                             5m0s
mesh-auth-mutual-connect-timeout                  5s
mesh-auth-mutual-enabled                          true
mesh-auth-mutual-listener-port                    4250
mesh-auth-queue-size                              1024
mesh-auth-rotated-identities-queue-size           1024
mesh-auth-spiffe-trust-domain                     spiffe.cilium
mesh-auth-spire-admin-socket                      /run/spire/sockets/admin.sock
mesh-auth-spire-agent-socket                      /run/spire/sockets/agent/agent.sock
mesh-auth-spire-server-address                    spire-server.cilium-spire.svc:8081
mesh-auth-spire-server-connection-timeout         30s

cilium config set debug true
```

https://github.com/cilium/cilium/issues/40533

## L7-Aware Traffic Management

[L7 Load Balancing and URL re-writing](https://docs.cilium.io/en/stable/network/servicemesh/envoy-traffic-management/)
```sh
helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
--set ingressController.enabled=true --set gatewayAPI.enabled=false \
--set envoyConfig.enabled=true  --set loadBalancer.l7.backend=envoy

k -n kube-system rollout restart deployment/cilium-operator
k -n kube-system rollout restart ds/cilium
k -n kube-system rollout restart ds/cilium-envoy

cilium config view |grep -i envoy
enable-envoy-config                               true
envoy-access-log-buffer-size                      4096
envoy-base-id                                     0
envoy-config-retry-interval                       15s
envoy-keep-cap-netbindservice                     false
envoy-secrets-namespace                           cilium-secrets
external-envoy-proxy                              true
loadbalancer-l7                                   envoy

cilium status --wait

# 샘플 앱 배포 
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/servicemesh/envoy/test-application.yaml

# 배포 상태 조회
kubectl get -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/servicemesh/envoy/test-application.yaml
NAME                          DATA   AGE
configmap/coredns-configmap   1      63s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/client           1/1     1            1           63s
deployment.apps/client2          1/1     1            1           63s
deployment.apps/echo-service-1   1/1     1            1           63s
deployment.apps/echo-service-2   1/1     1            1           63s

NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/echo-service-1   NodePort   10.96.32.59     <none>        8080:30447/TCP   63s
service/echo-service-2   NodePort   10.96.126.229   <none>        8080:32064/TCP   63s

export CLIENT2=$(kubectl get pods -l name=client2 -o jsonpath='{.items[0].metadata.name}')
echo $CLIENT2
client2-c97ddf6cf-ln6m7

cilium hubble port-forward&
hubble observe --from-pod $CLIENT2 -f

k exec -it $CLIENT2 -- curl -v echo-service-1:8080/
Aug 23 18:26:10.397: default/client2-c97ddf6cf-ln6m7:43144 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:26:10.397: default/client2-c97ddf6cf-ln6m7:43144 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:10.399: default/client2-c97ddf6cf-ln6m7:43144 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:10.406: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:10.406: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:10.408: default/client2-c97ddf6cf-ln6m7:43144 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-network FORWARDED (UDP)
Aug 23 18:26:10.408: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:10.409: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:10.412: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:26:10.412: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:26:10.413: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 23 18:26:10.414: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 23 18:26:10.414: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:26:10.415: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:10.415: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:10.415: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:10.420: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:10.420: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:10.422: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:26:10.425: default/client2-c97ddf6cf-ln6m7:45230 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK)

k exec -it $CLIENT2 -- curl -v echo-service-2:8080/
Aug 23 18:26:24.162: default/client2-c97ddf6cf-ln6m7:36925 (ID:1360) -> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:26:24.162: default/client2-c97ddf6cf-ln6m7:36925 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:24.163: default/client2-c97ddf6cf-ln6m7:36925 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:24.172: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:24.172: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:24.173: default/client2-c97ddf6cf-ln6m7:36925 (ID:1360) -> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) to-network FORWARDED (UDP)
Aug 23 18:26:24.173: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:24.173: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:24.177: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:26:24.177: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:26:24.177: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 23 18:26:24.178: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 23 18:26:24.180: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:24.180: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:24.180: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:24.180: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:26:24.184: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:24.184: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:24.188: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:26:24.189: default/client2-c97ddf6cf-ln6m7:59762 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK)
> 200 




k exec -it $CLIENT2 -- curl -v echo-service-1:8080/foo
Aug 23 18:26:36.607: default/client2-c97ddf6cf-ln6m7:46905 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:26:36.607: default/client2-c97ddf6cf-ln6m7:46905 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:36.609: default/client2-c97ddf6cf-ln6m7:46905 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:36.617: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:36.617: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:36.618: default/client2-c97ddf6cf-ln6m7:46905 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-network FORWARDED (UDP)
Aug 23 18:26:36.618: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:36.618: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:36.620: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:26:36.620: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:26:36.620: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 23 18:26:36.621: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 23 18:26:36.621: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:26:36.623: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:36.625: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:36.625: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:36.633: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:36.633: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs (ID:14334) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:36.638: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:26:36.639: default/client2-c97ddf6cf-ln6m7:41050 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-endpoint FORWARDED (TCP Flags: ACK)

k exec -it $CLIENT2 -- curl -v echo-service-2:8080/foo 
s-674b8bbfcf-lt55l:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:26:50.713: default/client2-c97ddf6cf-ln6m7:50187 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:50.714: default/client2-c97ddf6cf-ln6m7:50187 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:26:50.724: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:50.724: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:50.724: default/client2-c97ddf6cf-ln6m7:50187 (ID:1360) -> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) to-network FORWARDED (UDP)
Aug 23 18:26:50.724: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:26:50.724: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-lt55l:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:26:50.727: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:26:50.727: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:26:50.728: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 23 18:26:50.728: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 23 18:26:50.728: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:50.729: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:26:50.729: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:50.729: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:50.734: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:50.734: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc (ID:12688) pre-xlate-rev TRACED (TCP)
Aug 23 18:26:50.737: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:26:50.737: default/client2-c97ddf6cf-ln6m7:54330 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-endpoint FORWARDED (TCP Flags: ACK)
< HTTP/1.1 404 Not Found


# L7 정책 추가 
k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/servicemesh/envoy/client-egress-l7-http.yaml
k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/servicemesh/envoy/client-egress-only-dns.yaml


k exec -it $CLIENT2 -- curl -v echo-service-1:8080/
Aug 23 18:32:01.234: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:32:01.234: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:32:01.235: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:32:01.241: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:32:01.241: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:32:01.241: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)
Aug 23 18:32:01.241: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-proxy FORWARDED (UDP)
Aug 23 18:32:01.241: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:32:01.242: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:32:01.242: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:32:01.243: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:32:01.244: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. A)
Aug 23 18:32:01.244: default/client2-c97ddf6cf-ln6m7:33560 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. AAAA)
Aug 23 18:32:01.249: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:32:01.249: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:32:01.250: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) policy-verdict:L3-L4 EGRESS ALLOWED (TCP Flags: SYN)
Aug 23 18:32:01.250: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-proxy FORWARDED (TCP Flags: SYN)
Aug 23 18:32:01.250: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-proxy FORWARDED (TCP Flags: ACK)
Aug 23 18:32:01.250: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (TCP)
Aug 23 18:32:01.250: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:32:01.253: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) http-request FORWARDED (HTTP/1.1 GET http://echo-service-1:8080/)
Aug 23 18:32:01.261: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-proxy FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:32:01.263: default/client2-c97ddf6cf-ln6m7:51760 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) to-proxy FORWARDED (TCP Flags: ACK)
> 200 

k exec -it $CLIENT2 -- curl -v echo-service-2:8080/foo
Aug 23 18:34:10.044: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:34:10.044: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:34:10.044: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:34:10.053: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:34:10.053: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:34:10.053: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-proxy FORWARDED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:34:10.054: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-2.default.svc.cluster.local. A)
Aug 23 18:34:10.055: default/client2-c97ddf6cf-ln6m7:60437 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-2.default.svc.cluster.local. AAAA)
Aug 23 18:34:10.058: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:34:10.058: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) post-xlate-fwd TRANSLATED (TCP)
Aug 23 18:34:10.058: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) policy-verdict:L3-L4 EGRESS ALLOWED (TCP Flags: SYN)
Aug 23 18:34:10.058: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-proxy FORWARDED (TCP Flags: SYN)
Aug 23 18:34:10.058: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-proxy FORWARDED (TCP Flags: ACK)
Aug 23 18:34:10.059: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (TCP)
Aug 23 18:34:10.060: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:34:10.063: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) http-request DROPPED (HTTP/1.1 GET http://echo-service-2:8080/foo)
Aug 23 18:34:10.063: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-proxy FORWARDED (TCP Flags: ACK, FIN)
Aug 23 18:34:10.064: default/client2-c97ddf6cf-ln6m7:60752 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) to-proxy FORWARDED (TCP Flags: ACK)
> 403 Forebbidnen 

# 두 서비스간 요청 로드밸런싱 50:50 
# /foo url 요청 재작성 /
k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/servicemesh/envoy/envoy-traffic-management-test.yaml

# 요청 성공 
k exec -it $CLIENT2 -- curl -v echo-service-1:8080/foo
AAug 23 18:37:03.406: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:37:03.407: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:37:03.407: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-proxy FORWARDED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:37:03.415: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:37:03.416: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:37:03.416: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:37:03.417: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. AAAA)
Aug 23 18:37:03.417: default/client2-c97ddf6cf-ln6m7:38872 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. A)
Aug 23 18:37:03.421: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:37:03.421: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: SYN)
Aug 23 18:37:03.421: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK)
Aug 23 18:37:03.421: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:37:03.421: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (TCP)
Aug 23 18:37:03.424: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) -> default/echo-service-2-5df858689b-gsvfc:8080 (ID:12688) http-request FORWARDED (HTTP/1.1 GET http://echo-service-1:8080/)
Aug 23 18:37:03.429: default/client2-c97ddf6cf-ln6m7:43090 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK, FIN)


# foo가 아닌 경우 
kubectl exec -it $CLIENT2 -- curl -v echo-service-1:8080/bar
Aug 23 18:38:49.005: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) http-request DROPPED (HTTP/1.1 GET http://echo-service-1:8080/bar)

Aug 23 18:38:48.986: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-endpoint FORWARDED (UDP)
Aug 23 18:38:48.986: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:38:48.987: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p (ID:2869) pre-xlate-rev TRACED (UDP)
Aug 23 18:38:48.995: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:38:48.995: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. AAAA)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) to-proxy FORWARDED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) post-xlate-fwd TRANSLATED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:38:48.996: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (UDP)
Aug 23 18:38:48.997: default/client2-c97ddf6cf-ln6m7:60998 (ID:1360) -> kube-system/coredns-674b8bbfcf-rfk5p:53 (ID:2869) dns-request proxy FORWARDED (DNS Query echo-service-1.default.svc.cluster.local. A)
Aug 23 18:38:49.001: default/client2-c97ddf6cf-ln6m7 (ID:1360) <> default/echo-service-1:8080 (world) pre-xlate-fwd TRACED (TCP)
Aug 23 18:38:49.001: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: SYN)
Aug 23 18:38:49.002: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK)
Aug 23 18:38:49.002: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) <> 192.168.10.101 (host) pre-xlate-rev TRACED (TCP)
Aug 23 18:38:49.003: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 23 18:38:49.005: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1-867d69c679-bzdqs:8080 (ID:14334) http-request DROPPED (HTTP/1.1 GET http://echo-service-1:8080/bar)
Aug 23 18:38:49.008: default/client2-c97ddf6cf-ln6m7:48970 (ID:1360) -> default/echo-service-1:8080 (world) to-proxy FORWARDED (TCP Flags: ACK, FIN)
```

## [Gwctl](https://github.com/kubernetes-sigs/gwctl)
gateway, route 간 리소스 시각화
```sh
# go 설치 
sudo apt-get install make
wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version

# gwctl 설치 
git clone https://github.com/kubernetes-sigs/gwctl.git && cd gwctl
make build
export PATH="${PWD}/bin:${PATH}"
gwctl help

# Graph centered on a gateway
gwctl get gateway http-app-1 -o graph

# Graph centered on an HTTPRoute
gwctl get httproute http-app-1 -o graph

# 출력되는 DTO 데이터들은 DOT graph render 사이트에서 그래프형태로 변환할수 있따.
```