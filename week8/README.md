## [Cilium Study 1기] 8주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 8주차 스터디에 대한 정리 글입니다. 

```sh
vagrant up

vagrant ssh k8s-ctr

# 프로메테우스
http://192.168.10.100:30001 
# 그라파나
http://192.168.10.100:30002  
# 허블 UI
http://192.168.10.100:30003  

vagrant destroy && rm -rf .vagrant
```

## [Cilium Security](https://docs.cilium.io/en/stable/security/network/policyenforcement/#default-security-policy)

- 정책이 설정되지 않은 경우 모든 통신이 허용되지만, 정책이 설정되는 순간 모든 통신은 거부된다.

```sh
# k8s 환경에서는 ip로 보안 정책을 구성할수 없다. 따라서 엔드포엔트마다 고유의 ID를 할당받아 네트워크 정책을 구성한다 
k get ciliumendpoints.cilium.io -n kube-system
NAME                              SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
coredns-674b8bbfcf-44p82          22342               ready            172.20.0.176
coredns-674b8bbfcf-g7v7r          22342               ready            172.20.0.209
hubble-relay-fdd49b976-87vdz      34860               ready            172.20.0.128
hubble-ui-655f947f96-msjdb        16037               ready            172.20.0.182
metrics-server-5dd7b49d79-6hfhb   19366               ready            172.20.0.230

# 엔드포인트마다 ID를 공유한다.
k get ciliumidentities.cilium.io 
NAME    NAMESPACE            AGE
16037   kube-system          50m
18599   local-path-storage   50m
19366   kube-system          50m
22342   kube-system          50m
34860   kube-system          50m
4108    cilium-monitoring    50m
52823   cilium-monitoring    50m

# id는 무엇을 기준으로 생성될까? 바로 레이블을 기반으로 생성된다.
# security-labels의 app에 해당하는 레이블을 기준으로 생성되며 레이블이 변경 시마다 자동으로 수정된다.
k get ciliumidentities.cilium.io 19366 -o yaml | yq
{
  "apiVersion": "cilium.io/v2",
  "kind": "CiliumIdentity",
  "metadata": {
    "creationTimestamp": "2025-09-01T01:20:13Z",
    "generation": 1,
    "labels": {
      "io.kubernetes.pod.namespace": "kube-system"
    },
    "name": "19366",
    "resourceVersion": "797",
    "uid": "28e4d6fe-ef7c-4d96-8cc6-f01e4b6e910c"
  },
  "security-labels": {
    "k8s:app.kubernetes.io/instance": "metrics-server",
    "k8s:app.kubernetes.io/name": "metrics-server",

    "k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name": "kube-system",
    "k8s:io.cilium.k8s.policy.cluster": "default",
    "k8s:io.cilium.k8s.policy.serviceaccount": "metrics-server",
    "k8s:io.kubernetes.pod.namespace": "kube-system"
  }
}

# id에 대한 라벨 
k exec -it -n kube-system ds/cilium -- cilium identity list
19366   k8s:app.kubernetes.io/instance=metrics-server
        k8s:app.kubernetes.io/name=metrics-server
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=kube-system
        k8s:io.cilium.k8s.policy.cluster=default
        k8s:io.cilium.k8s.policy.serviceaccount=metrics-server
        k8s:io.kubernetes.pod.namespace=kube-system

# 라벨 조회
K get pod -n kube-system -l app.kubernetes.io/name=metrics-server --show-labels
metrics-server-5dd7b49d79-6hfhb   1/1     Running   0          57m   app.kubernetes.io/instance=metrics-server,app.kubernetes.io/name=metrics-server,pod-template-hash=5dd7b49d79

# 레이블을 새롭게 추가
kubectl label pods -n kube-system -l app.kubernetes.io/name=metrics-server study=8w

# ID가 수정되는 것을 확인할 수 있따.
k get ciliumendpoints.cilium.io -n kube-system
metrics-server-5dd7b49d79-6hfhb   18949               ready            172.20.0.230

# 더욱 신기한 점은 보안 ID는 수정되었으나 리스트에는 아직 존재한다.
# 즉 메트릭 서버에 대한 id가 새롭게 추가되었다.
k exec -it -n kube-system ds/cilium -- cilium identity list
18949   k8s:app.kubernetes.io/instance=metrics-server
        k8s:app.kubernetes.io/name=metrics-server
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=kube-system
        k8s:io.cilium.k8s.policy.cluster=default
        k8s:io.cilium.k8s.policy.serviceaccount=metrics-server
        k8s:io.kubernetes.pod.namespace=kube-system
        k8s:study=8w
19366   k8s:app.kubernetes.io/instance=metrics-server
        k8s:app.kubernetes.io/name=metrics-server
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=kube-system
        k8s:io.cilium.k8s.policy.cluster=default
        k8s:io.cilium.k8s.policy.serviceaccount=metrics-server
        k8s:io.kubernetes.pod.namespace=kube-system

# 레이블 수정
k edit deploy -n kube-system metrics-server
...
  template:
    metadata:
      labels:
        app: test
        k8s-app: kube-dns
...


# 새로운 정책 적용
k exec -it -n kube-system ds/cilium -- cilium identity list
2478    k8s:app.kubernetes.io/instance=metrics-server
        k8s:app.kubernetes.io/name=metrics-server
        k8s:app=teset
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=kube-system
        k8s:io.cilium.k8s.policy.cluster=default
        k8s:io.cilium.k8s.policy.serviceaccount=metrics-server
        k8s:io.kubernetes.pod.namespace=kube-system

# ciliium 관리하는 모든 엔드포인트에는 ID가 할당된다. 이중 reserved는 예약된 ID를 의미한다.
k exec -it -n kube-system ds/cilium -- cilium identity list
1       reserved:host
        reserved:kube-apiserver
2       reserved:world
3       reserved:unmanaged
4       reserved:health
5       reserved:init
6       reserved:remote-node
7       reserved:kube-apiserver
        reserved:remote-node
8       reserved:ingress
9       reserved:world-ipv4
10      reserved:world-ipv6
```

## DNS 기반 보안 정책 
```sh
# 샘플 APP 배포
cat << EOF > dns-sw-app.yaml
apiVersion: v1
kind: Pod
metadata:
  name: mediabot
  labels:
    org: empire
    class: mediabot
    app: mediabot
spec:
  containers:
  - name: mediabot
    image: quay.io/cilium/json-mock:v1.3.8@sha256:5aad04835eda9025fe4561ad31be77fd55309af8158ca8663a72f6abb78c2603
EOF

k apply -f dns-sw-app.yaml

k wait pod/mediabot --for=condition=Ready
pod/mediabot condition met

# mediabot의 ID 조회
k exec -it -n kube-system ds/cilium -- cilium identity list
27541   k8s:app=mediabot
        k8s:class=mediabot
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
        k8s:io.cilium.k8s.policy.cluster=default
        k8s:io.cilium.k8s.policy.serviceaccount=default
        k8s:io.kubernetes.pod.namespace=default
        k8s:org=empire

# 모든 요청이 200 ~ 300이다.
open http://192.168.10.100:30003/
k exec mediabot -- curl -I -s https://api.github.com | head -1
HTTP/2 200

k exec mediabot -- curl -I -s --max-time 5 https://support.github.com | head -1
HTTP/2 302
```


### DNS Egress 적용 1
```sh
# mediabot 파드가 api.github.com에만 액세스 허용되도록 정책 생성
cat << EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "fqdn"
spec:
  endpointSelector:
    matchLabels:
      org: empire
      class: mediabot
  egress:
  - toFQDNs:
    - matchName: "api.github.com"
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": kube-system
        "k8s:k8s-app": kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"
EOF

# 정책 조회
k get cnp
fqdn   18s   True

# cilium 정책 셀럭터 및 ID
k exec -it -n kube-system ds/cilium -- cilium policy selectors 
SELECTOR                                                                                                                                                                      LABELS         USERS   IDENTITIES
&LabelSelector{MatchLabels:map[string]string{any.class: mediabot,any.org: empire,k8s.io.kubernetes.pod.namespace: default,},MatchExpressions:[]LabelSelectorRequirement{},}   default/fqdn   1       27541


# cilium의 경우 FQNS을 생성하면 dns-proxy가 할성화된다.
cilium config view | grep -i dns
dnsproxy-enable-transparent-mode                  true
dnsproxy-socket-linger-timeout                    10
hubble-metrics                                    dns drop tcp flow port-distribution icmp httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction
tofqdns-dns-reject-response-code                  refused
tofqdns-enable-dns-compression                    true
tofqdns-endpoint-max-ip-per-hostname              1000
tofqdns-idle-connection-grace-period              0s
tofqdns-max-deferred-connection-deletes           10000
tofqdns-preallocate-identities                    true
tofqdns-proxy-response-max-delay                  100ms

# 접근 성공
k exec mediabot -- curl -I -s https://api.github.com | head -1
HTTP/2 200

# 접근 실패
kubectl exec mediabot -- curl -I -s --max-time 5 https://support.github.com | head -1
command terminated with exit code 28

# 허블 조회
cilium hubble port-forward&
hubble observe --pod mediabot

# dns-proxy는 cilium-agent 내에 go로 구현되어있다.
# mediabot -> world로 접근되지 않고 중간에 dns-proxy이가 요청을 가로챈다. 이때 캐시도 처리한다.
Sep  1 02:36:13.439: default/mediabot:34034 (ID:27541) <- kube-system/coredns-674b8bbfcf-44p82:53 (ID:22342) dns-response proxy FORWARDED (DNS Answer  TTL: 4294967295 (Proxy support.github.com. AAAA))
Sep  1 02:36:13.439: default/mediabot:34034 (ID:27541) <- kube-system/coredns-674b8bbfcf-44p82:53 (ID:22342) dns-response proxy FORWARDED (DNS Answer "185.199.108.133,185.199.110.133,185.199.109.133,185.199.111.133" TTL: 30 (Proxy support.github.com. A))

# api.github.com외에는 접근이 거부된다.
Sep  1 02:36:14.453: default/mediabot:33018 (ID:27541) <> support.github.com:443 (world) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Sep  1 02:36:14.453: default/mediabot:33018 (ID:27541) <> support.github.com:443 (world) Policy denied DROPPED (TCP Flags: SYN)

k9s -> configmap (coredns) : log 추가
k rollout -n kube-system restart deployment coredns

# coredns 로그 조회
k logs -n kube-system -l k8s-app=kube-dns -f

# dns-prxoy 캐싱 동작 여부 테스트
# 그러나 coredns에서 계속해서 로그가 찍힌다. 즉 캐시가 동작하지 않는 것으로 보인다.
k exec mediabot -- curl -I -s https://api.github.com | head -1
k exec mediabot -- curl -I -s https://api.github.com | head -1

# cilium도 재시작해주엇으나 마찬가지이다.
k rollout -n kube-system restart ds cilium

hubble observe --pod mediabot

## cilium 단축키 지정
export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w2  -o jsonpath='{.items[0].metadata.name}')
echo $CILIUMPOD0 $CILIUMPOD1 $CILIUMPOD2
alias c0="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium"
alias c1="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium"
alias c2="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- cilium"

# FDQN 캐시 조회
c0 fqdn cache list
c1 fqdn cache list
c2 fqdn cache list
Endpoint   Source       FQDN                  TTL   ExpirationTime             IPs
2770       connection   support.github.com.   0     2025-09-01T02:56:41.413Z   185.199.108.133
2770       connection   support.github.com.   0     2025-09-01T02:56:41.413Z   185.199.109.133
2770       connection   support.github.com.   0     2025-09-01T02:56:41.413Z   185.199.110.133
2770       connection   support.github.com.   0     2025-09-01T02:56:41.413Z   185.199.111.133
2770       connection   api.github.com.       0     2025-09-01T02:56:41.413Z   20.200.245.245  

c0 fqdn names
c1 fqdn names
c2 fqdn names
{
  "DNSPollNames": null,
  "FQDNPolicySelectors": [
    {
      "regexString": "^api[.]github[.]com[.]$",
      "selectorString": "MatchName: api.github.com, MatchPattern: "
    }
  ]
}
```

### DNS Egress 적용 2
```sh
### 모든 GitHub 하위 도메인(예: 패턴)에 액세스 허용 설정
# 기존 cnp 및 fdqn 캐시 초기화
k delete cnp fqdn
c0 fqdn cache clean -f
c1 fqdn cache clean -f
c2 fqdn cache clean -f

# CNP yaml 설정
# github의 하위 도메인에 대해서 접근이 가능하다.
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "fqdn"
spec:
  endpointSelector:
    matchLabels:
      org: empire
      class: mediabot
  egress:
  - toFQDNs:
    - matchName: "*.github.com"
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": kube-system
        "k8s:k8s-app": kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"

k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes-dns/dns-pattern.yaml

# fdqn 조회
c1 fqdn names
c2 fqdn names
{
  "DNSPollNames": null,
  "FQDNPolicySelectors": [
    {
      "regexString": "^[-a-zA-Z0-9_]*[.]github[.]com[.]$",
      "selectorString": "MatchName: , MatchPattern: *.github.com"
    }
  ]
}

c0 fqdn cache list
c1 fqdn cache list
c2 fqdn cache list

k get cnp
NAME   AGE   VALID
fqdn   13s   True

kubectl exec mediabot -- curl -I -s https://support.github.com | head -1
HTTP/2 302

kubectl exec mediabot -- curl -I -s https://gist.github.com | head -1
HTTP/2 302

# 만일 해당 요청이 200 액세스가 발생되는 경우는 캐시로 보인다. cilium, coredns, mediabot를 파드를 재시작한 결과 정상적으로 동작한다. 
kubectl exec mediabot -- curl -I -s --max-time 5 https://github.com | head -1
command terminated with exit code 28

kubectl exec mediabot -- curl -I -s --max-time 5 https://cilium.io| head -1
command terminated with exit code 28
```

### DNS Egress 적용 3
```sh
# dns-port 설정
# github 하위 서비스에 443 포트만 접근가능하도록 설정한다.
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "fqdn"
spec:
  endpointSelector:
    matchLabels:
      org: empire
      class: mediabot
  egress:
  - toFQDNs:
    - matchPattern: "*.github.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": kube-system
        "k8s:k8s-app": kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"

# 배포
k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes-dns/dns-port.yaml

c0 fqdn names
c1 fqdn names
c2 fqdn names
{
  "DNSPollNames": null,
  "FQDNPolicySelectors": [
    {
      "regexString": "^[-a-zA-Z0-9_]*[.]github[.]com[.]$",
      "selectorString": "MatchName: , MatchPattern: *.github.com"
    }
  ]
}

# 요청 성공
k exec mediabot -- curl -I -s https://support.github.com | head -1
HTTP/2 302

# 80포트이기에 실패가 발생된다.
k exec mediabot -- curl -I -s --max-time 5 http://support.github.com | head -1
command terminated with exit code 28

# 캐시 초기화
c1 fqdn cache list
c2 fqdn cache list
c1 fqdn cache clean -f
c2 fqdn cache clean -f

# 배포된 정책 및 리소스 삭제
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes-dns/dns-sw-app.yaml
kubectl delete cnp fqdn
```

## WireGuard
- 동일 노드 내에서 파드 간 통신에는 암호화되지 않는다.
  - 터널링 모드에서는 2번의 캡슐화가 이뤄진다.
- WireGuard는 UDP, port 51871로 통신한다.
- 각 노드는 자체 암호화 키 쌍을 생성해 `CiliumNode`에 `network.cilium.io/wg-pub-key`으로 공개 키를 주고 받는다.

```sh
# 샘플 애플리케이션 배포 및 동작 확인
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


# 배포 확인
kubectl get deploy,svc,ep webpod -owide
kubectl get endpointslices -l app=webpod
kubectl get ciliumendpoints # IP 확인

# 통신 확인
kubectl exec -it curl-pod -- curl -s --connect-timeout 1 webpod | grep Hostname
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# cilium-dbg, map
kubectl exec -n kube-system ds/cilium -- cilium-dbg ip list
kubectl exec -n kube-system ds/cilium -- cilium-dbg endpoint list
kubectl exec -n kube-system ds/cilium -- cilium-dbg service list
kubectl exec -n kube-system ds/cilium -- cilium-dbg bpf lb list
kubectl exec -n kube-system ds/cilium -- cilium-dbg bpf nat list
kubectl exec -n kube-system ds/cilium -- cilium-dbg map list | grep -v '0             0'
kubectl exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_services_v2
kubectl exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_backends_v3
kubectl exec -n kube-system ds/cilium -- cilium-dbg map get cilium_lb4_reverse_nat
kubectl exec -n kube-system ds/cilium -- cilium-dbg map get cilium_ipcache_v2
```

### WireGuard 설정
```sh
# 요구사항 커널 버전 5.6 이상
uname -ar
Linux k8s-ctr 6.8.0-64-generic 67-Ubuntu SMP PREEMPT_DYNAMIC Sun Jun 15 20:23:31 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux

grep -E 'CONFIG_WIREGUARD=m' /boot/config-$(uname -r)
CONFIG_WIREGUARD=m

# 배포 전 네트워크 인터페이스 확인
ip -c addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 08:00:27:6d:e2:c4 brd ff:ff:ff:ff:ff:ff
    altname enp0s3
    inet 10.0.2.15/24 metric 100 brd 10.0.2.255 scope global dynamic eth0
       valid_lft 74404sec preferred_lft 74404sec
    inet6 fd17:625c:f037:2:a00:27ff:fe6d:e2c4/64 scope global dynamic mngtmpaddr noprefixroute
       valid_lft 86204sec preferred_lft 14204sec
    inet6 fe80::a00:27ff:fe6d:e2c4/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 08:00:27:b5:e6:c4 brd ff:ff:ff:ff:ff:ff
    altname enp0s8
    inet 192.168.10.100/24 brd 192.168.10.255 scope global eth1
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:feb5:e6c4/64 scope link
       valid_lft forever preferred_lft forever
4: cilium_net@cilium_host: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 7a:13:e8:aa:77:79 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::7813:e8ff:feaa:7779/64 scope link
       valid_lft forever preferred_lft forever
5: cilium_host@cilium_net: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 7e:9f:cf:26:45:d8 brd ff:ff:ff:ff:ff:ff
    inet 172.20.0.154/32 scope global cilium_host
       valid_lft forever preferred_lft forever
    inet6 fe80::7c9f:cfff:fe26:45d8/64 scope link
       valid_lft forever preferred_lft forever

ip -c route
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
172.20.0.18 dev lxc5d64df0db676 proto kernel scope link
172.20.0.26 dev lxc39bf5fcd9700 proto kernel scope link
172.20.0.36 dev lxce188697f1d2b proto kernel scope link
172.20.0.69 dev lxcf3fadb3aafab proto kernel scope link
172.20.0.96 dev lxcf92616063717 proto kernel scope link
172.20.0.116 dev lxcf26ffa997f7d proto kernel scope link
172.20.0.128 dev lxc1b3df00ac2f6 proto kernel scope link
172.20.0.182 dev lxc9833cc7f2fe0 proto kernel scope link
172.20.1.0/24 via 192.168.10.101 dev eth1 proto kernel
172.20.2.0/24 via 192.168.10.102 dev eth1 proto kernel

ip rule show
9:      from all fwmark 0x200/0xf00 lookup 2004
10:     from all fwmark 0xa00/0xf00 lookup 2005
100:    from all lookup local
32766:  from all lookup main
32767:  from all lookup default

# wireguart 배포 
helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
  --set encryption.enabled=true --set encryption.type=wireguard

k -n kube-system rollout restart ds/cilium

cilium config view | grep -i wireguard
enable-wireguard                                  true
wireguard-persistent-keepalive                    0s

# 피어의 수는 노드 수에서 -1 한 값과 동일해야 한다. 현재 노드의 수는 3개이기에 출력 값은 2가 정상이다.
k exec -it -n kube-system ds/cilium -- cilium encrypt status
Encryption: Wireguard
Interface: cilium_wg0
        Public key: kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=
        Number of peers: 2

k exec -it -n kube-system ds/cilium -- cilium status | grep Encryption
Encryption:              Wireguard   [NodeEncryption: Disabled, cilium_wg0 (Pubkey: kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=, Port: 51871, Peers: 2)]

k exec -it -n kube-system ds/cilium -- cilium debuginfo --output json
k exec -it -n kube-system ds/cilium -- cilium debuginfo --output json | jq .encryption

ip -d -c addr show cilium_wg0
28: cilium_wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default
    link/none  promiscuity 0  allmulti 0 minmtu 0 maxmtu 2147483552
    wireguard numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536

ip rule show
9:      from all fwmark 0x200/0xf00 lookup 2004
10:     from all fwmark 0xa00/0xf00 lookup 2005
100:    from all lookup local
32766:  from all lookup main
32767:  from all lookup default

wg -h

# wg 정보 조회
# 상대방의 정보를 IP가 아닌 Peer로 인지한다.
wg show
interface: cilium_wg0
  public key: NI1mGHWb5nR/3l+s+3JwDExK0qk6601GKlzDzQhHFHs=
  private key: (hidden)
  listening port: 51871
  fwmark: 0xe00
peer: kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=
  endpoint: 192.168.10.101:51871
  allowed ips: 172.20.1.128/32, 172.20.1.145/32, 192.168.10.101/32, 172.20.1.140/32, 172.20.1.230/32, 172.20.1.0/24
peer: PzxxFD9rvKzC3pqk914qaBRLp7FZqZ7ajNqbOmhBqiY=
  endpoint: 192.168.10.102:51871
  allowed ips: 172.20.2.30/32, 192.168.10.102/32, 172.20.2.80/32, 172.20.2.42/32, 172.20.2.0/24

wg show all public-key
cilium_wg0      NI1mGHWb5nR/3l+s+3JwDExK0qk6601GKlzDzQhHFHs=

wg show all private-key
cilium_wg0      gMlyrYMLFUROm0sbq2o9/F7vuHrONRlLwulIDbg17lg=

wg show all preshared-keys
cilium_wg0      kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=    (none)
cilium_wg0      PzxxFD9rvKzC3pqk914qaBRLp7FZqZ7ajNqbOmhBqiY=    (none)

wg show all endpoints
cilium_wg0      kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=    192.168.10.101:51871
PzxxFD9rvKzC3pqk914qaBRLp7FZqZ7ajNqbOmhBqiY=    192.168.10.102:51871

wg show all transfer
cilium_wg0      kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=    0       0
cilium_wg0      PzxxFD9rvKzC3pqk914qaBRLp7FZqZ7ajNqbOmhBqiY=    0       0


# 공개 키 조회
k get cn -o yaml | grep annotations -A1
  annotations:
    network.cilium.io/wg-pub-key: NI1mGHWb5nR/3l+s+3JwDExK0qk6601GKlzDzQhHFHs=
--
  annotations:
    network.cilium.io/wg-pub-key: kkmwNHmH8/nXfN/5jP8Z2iVy2aT7W4SB7njkWPsT4xU=
--
  annotations:
    network.cilium.io/wg-pub-key: PzxxFD9rvKzC3pqk914qaBRLp7FZqZ7ajNqbOmhBqiY=

# 통신 확인
k exec -it curl-pod -- curl webpod
k exec -it curl-pod -- curl webpod

# 패킷 조회
# pod -> cilium_wg0 -> world
tcpdump -i cilium_wg0 -n
listening on cilium_wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
13:45:48.395625 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [S], seq 3216450333, win 64860, options [mss 1380,sackOK,TS val 4123083937 ecr 0,nop,wscale 7], length 0
13:45:48.396773 IP 172.20.1.145.80 > 172.20.0.18.50672: Flags [S.], seq 754334218, ack 3216450334, win 64296, options [mss 1380,sackOK,TS val 1249873686 ecr 4123083937,nop,wscale 7], length 0
13:45:48.396921 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [.], ack 1, win 507, options [nop,nop,TS val 4123083939 ecr 1249873686], length 0
13:45:48.397070 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [P.], seq 1:71, ack 1, win 507, options [nop,nop,TS val 4123083939 ecr 1249873686], length 70: HTTP: GET / HTTP/1.1
13:45:48.397926 IP 172.20.1.145.80 > 172.20.0.18.50672: Flags [.], ack 71, win 502, options [nop,nop,TS val 1249873687 ecr 4123083939], length 0
13:45:48.399600 IP 172.20.1.145.80 > 172.20.0.18.50672: Flags [P.], seq 1:321, ack 71, win 502, options [nop,nop,TS val 1249873689 ecr 4123083939], length 320: HTTP: HTTP/1.1 200 OK
13:45:48.399702 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [.], ack 321, win 505, options [nop,nop,TS val 4123083942 ecr 1249873689], length 0
13:45:48.400633 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [F.], seq 71, ack 321, win 505, options [nop,nop,TS val 4123083943 ecr 1249873689], length 0
13:45:48.402966 IP 172.20.1.145.80 > 172.20.0.18.50672: Flags [F.], seq 321, ack 72, win 502, options [nop,nop,TS val 1249873692 ecr 4123083943], length 0
13:45:48.403215 IP 172.20.0.18.50672 > 172.20.1.145.80: Flags [.], ack 322, win 505, options [nop,nop,TS val 4123083945 ecr 1249873692], length 0

tcpdump -eni any udp port 51871
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
13:46:30.193093 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 144: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 96
13:46:30.193233 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 196: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 148
13:46:30.194811 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 140: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 92
13:46:30.195072 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 144: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 96
13:46:30.195340 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 80: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 32
13:46:30.195716 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 208: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 160
13:46:30.195758 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 144: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 96
13:46:30.196574 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 144: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 96
13:46:30.196574 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 144: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 96
13:46:30.197899 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 464: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 416
13:46:30.198430 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 144: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 96
13:46:30.199525 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 144: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 96
13:46:30.200458 eth1  In  ifindex 3 08:00:27:0a:a6:82 ethertype IPv4 (0x0800), length 144: 192.168.10.101.51871 > 192.168.10.100.51871: UDP, length 96
13:46:30.201123 eth1  Out ifindex 3 08:00:27:b5:e6:c4 ethertype IPv4 (0x0800), length 144: 192.168.10.100.51871 > 192.168.10.101.51871: UDP, length 96

tcpdump -eni any udp port 51871 -w /tmp/wg.pcap 

# HOST에서 작업한다.
vagrant plugin install vagrant-scp
vagrant scp k8s-ctr:/tmp/wg.pcap . 

hubble observe --pod curl-pod

# 설정 복구
helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
  --set encryption.enabled=false

k -n kube-system rollout restart ds/cilium

# wireguard 설정 복구 조회
cilium config view | grep -i wireguard
Encryption: Disabled

k exec -it -n kube-system ds/cilium -- cilium encrypt status
Encryption:              Disabled
```

## [Inspecting TLS Encrypted Connections with Cilium](https://docs.cilium.io/en/stable/security/tls-visibility/)
![](https://docs.cilium.io/en/stable/_images/cilium-tls-interception.png)

https 트래픽을 통제하기 위한 방식으로 인증서에 대한 처리가 필요하다. 이러한 요청 처리를 envoy가 담당한다. `NPDS`과 `SDS` 중 `SDS`를 권장한다.

동작 과정
1. 내부 인증 기관(CA) 생성 및 CA 개인키 and CA 인증서 생성
2. TLS 검사 대상(http.bing)으로 개인 및 인증서 서명 요청 
3. CA 개인 키를 활용한 서명된 인증서 생성
4. tls가 동작하는 클라이언트에서 CA를 신뢰
5. cilium에게 신뢰가능한 ca 집한 정보 제공 


```sh
k get all,secret,cm -n cilium-secrets
NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      3h50m

cat << EOF > tls-config.yaml
tls:
  readSecretsOnlyFromSecretsNamespace: true
  secretsNamespace:
    name: cilium-secrets # This setting is optional, as it is the default
  secretSync:
    enabled: true
EOF

helm upgrade cilium cilium/cilium --version 1.18.1 --namespace kube-system --reuse-values \
-f tls-config.yaml

k -n kube-system rollout restart deploy/cilium-operator
k -n kube-system rollout restart ds/cilium

cilium config view | grep -i secret
enable-ingress-secrets-sync                       true
enable-policy-secrets-sync                        true
ingress-secrets-namespace                         cilium-secrets
policy-secrets-namespace                          cilium-secrets
policy-secrets-only-from-secrets-namespace        true
```

### [tls Interception](https://docs.cilium.io/en/stable/security/tls-visibility/#deploy-the-demo-application)

```sh
cat << EOF > dns-sw-app.yaml
apiVersion: v1
kind: Pod
metadata:
  name: mediabot
  labels:
    org: empire
    class: mediabot
    app: mediabot
spec:
  containers:
  - name: mediabot
    image: quay.io/cilium/json-mock:v1.3.8@sha256:5aad04835eda9025fe4561ad31be77fd55309af8158ca8663a72f6abb78c2603
EOF

k apply -f dns-sw-app.yaml

k wait pod/mediabot --for=condition=Ready
pod/mediabot condition met

k get pods
NAME                      READY   STATUS    RESTARTS   AGE
curl-pod                  1/1     Running   0          103m
mediabot                  1/1     Running   0          17s
webpod-697b545f57-dkknx   1/1     Running   0          103m
webpod-697b545f57-n7nmk   1/1     Running   0          103m

k exec mediabot -- curl -I -s https://api.github.com | head -1
HTTP/2 200

k exec mediabot -- curl -I -s --max-time 5 https://support.github.com | head -1
HTTP/2 302

# 1. 내부 인증기관 생성
## CA 개인 키 생성
openssl genrsa -des3 -out myCA.key 2048
Enter PEM pass phrase: qwer1234
Verifying - Enter PEM pass phrase: qwer1234

## CA 인증서 생성  
openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.crt
Enter pass phrase for myCA.key: qwer1234
Country Name (2 letter code) [AU]:kr
State or Province Name (full name) [Some-State]:seoul
Locality Name (eg, city) []:seoul
Organization Name (eg, company) [Internet Widgits Pty Ltd]:clod
Organizational Unit Name (eg, section) []:study
Common Name (e.g. server FQDN or YOUR name) []:clond.net
Email Address []:

## 개인 키 조회
ls *.key
myCA.key

## 인증서 조회
ls *.crt
myCA.crt

## CA 정보 조회
openssl x509 -in myCA.crt -noout -text
Issuer: C = kr, ST = seoul, L = seoul, O = clod, OU = study, CN = clond.net
        Validity
            Not Before: Sep  1 05:12:59 2025 GMT
            Not After : Aug 31 05:12:59 2030 GMT
        Subject: C = kr, ST = seoul, L = seoul, O = clod, OU = study, CN = clond.net
        X509v3 Basic Constraints: critical
                CA:TRUE

# 2. TLS 검사 대상(http.bing)으로 개인 및 인증서 서명 요청 
## 개인 키 생성
openssl genrsa -out internal-httpbin.key 2048

ls internal-httpbin.key
internal-httpbin.key

## 인증서 생성
openssl req -new -key internal-httpbin.key -out internal-httpbin.csr
Common Name (e.g. server FQDN or YOUR name) []:httpbin.org

# 3. CA를 활용 서명된 인증서 생성
openssl x509 -req -days 360 -in internal-httpbin.csr -CA myCA.crt -CAkey myCA.key -CAcreateserial -out internal-httpbin.crt -sha256
Certificate request self-signature ok
subject=C = KR, ST = Seoul, L = Seoul, O = cloudneta, OU = study, CN = httpbin.org
Enter pass phrase for myCA.key: qwer1234

## 인증서 조회
ls internal-httpbin.crt
    Issuer: C = kr, ST = seoul, L = seoul, O = clod, OU = study, CN = clond.net
    Validity
        Not Before: Sep  1 05:16:10 2025 GMT
        Not After : Aug 27 05:16:10 2026 GMT
    Subject: C = kr, ST = seoul, L = seoul, O = cloundnet, OU = study, CN = httpbin.org

## 시크릿 생성
k create secret tls httpbin-tls-data -n kube-system --cert=internal-httpbin.crt --key=internal-httpbin.key
k get secret -n kube-system  httpbin-tls-data

# 4. 클라이언트 파드에서 내부 CA를 신뢰할수 있는 CA로 추가 
k exec -it mediabot -- ls -l /usr/local/share/ca-certificates/
total 0

## 클라이언트 파드 내에서 신뢰할수 잇는 CA로 내부 CA 추가
k cp myCA.crt default/mediabot:/usr/local/share/ca-certificates/myCA.crt

## CA 인증서 조회
k exec -it mediabot -- ls -l /usr/local/share/ca-certificates/
-rw-r--r-- 1 root root 1318 Sep  1 05:17 myCA.crt

## 사이즈 및 생성 날짜 조회
k exec -it mediabot -- ls -l /etc/ssl/certs/ca-certificates.crt
-rw-r--r-- 1 root root 213777 Jan  9  2024 /etc/ssl/certs/ca-certificates.crt

## 신뢰할수 있는 인증기관 추가에 대한 업데이트
k exec mediabot -- update-ca-certificates

## 사이즈 및 생성 날짜 조회
k exec -it mediabot -- ls -l /etc/ssl/certs/ca-certificates.crt
-rw-r--r-- 1 root root 215095 Sep  1 05:18 /etc/ssl/certs/ca-certificates.crt

# 5. cilium이 신뢰할수 있는 CA 목록 제공
k cp default mediabot:/etc/ssl/certs/ca-certificates.crt ca-certificates.crt

## 시크릿 생성 
k create secret generic tls-orig-data -n kube-system --from-file=ca.crt=./ca-certificates.crt

k get secret -n kube-system tls-orig-data
NAME            TYPE     DATA   AGE
tls-orig-data   Opaque   1      8s

hubble observe --pod mediabot -f

k get pods

k exec -it mediabot -- curl -sL 'https://httpbin.org/anything'
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.88.1",
    "X-Amzn-Trace-Id": "Root=1-68b52dbf-42bac1d66ba4f66611f4beea"
  },
  "json": null,
  "method": "GET",
  "origin": "220.120.28.18",
  "url": "https://httpbin.org/anything"
}

## 인증서 정보 출력
k exec -it mediabot -- curl -sL 'https://httpbin.org/headers' -v
* Server certificate:
*  subject: CN=httpbin.org
*  start date: Jul 20 00:00:00 2025 GMT
*  expire date: Aug 17 23:59:59 2026 GMT
*  subjectAltName: host "httpbin.org" matched cert's "httpbin.org"
*  issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M03
*  SSL certificate verify ok. '

## 정책 적용
k create -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes-tls-inspection/l7-visibility-tls.yaml

k get cnp
NAME                AGE   VALID
l7-visibility-tls   4s    True

hubble observe --pod mediabot -f

## https임에도 불과하고 L7 정보가 담겨있는 것을 확인할 수 있다.
k exec -it mediabot -- curl -sL 'https://httpbin.org/anything'
...
Sep  1 05:26:31.879: default/mediabot:57502 (ID:14979) -> httpbin.org:443 (ID:16777217) http-request FORWARDED (HTTP/1.1 GET https://httpbin.org/anything)
Sep  1 05:26:32.455: default/mediabot:57502 (ID:14979) <- httpbin.org:443 (ID:16777217) http-response FORWARDED (HTTP/1.1 200 576ms (GET https://httpbin.org/anything))
...

## 서버 인증서 정보 확인
k exec -it mediabot -- curl -sL 'https://httpbin.org/headers' -v
* Server certificate:
*  subject: C=kr; ST=seoul; L=seoul; O=cloundnet; OU=study; CN=httpbin.org
*  start date: Sep  1 05:16:10 2025 GMT
*  expire date: Aug 27 05:16:10 2026 GMT
*  common name: httpbin.org (matched)
*  issuer: C=kr; ST=seoul; L=seoul; O=clod; OU=study; CN=clond.net
*  SSL certificate verify ok.

## 정책 리소스 및 시크릿 삭제 
k delete -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes-dns/dns-sw-app.yaml
k delete cnp l7-visibility-tls
k delete secret -n kube-system tls-orig-data
k delete secret -n kube-system httpbin-tls-data
```

## [Tetragon](https://tetragon.io/docs/overview/)
```sh
# tetragon 배포
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon -n kube-system
kubectl rollout status -n kube-system ds/tetragon -w

# tetragon 배포 확인
k -n kube-system get deploy tetragon-operator -owide
NAME                READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS          IMAGES                                    SELECTOR
tetragon-operator   1/1     1            1           39s   tetragon-operator   quay.io/cilium/tetragon-operator:v1.5.0   app.kubernetes.io/instance=tetragon,app.kubernetes.io/name=tetragon-operator

k -n kube-system get cm tetragon-operator-config tetragon-config
NAME                       DATA   AGE
tetragon-operator-config   9      73s
tetragon-config            33     73s

k -n kube-system get ds tetragon -owide
NAME       DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE   CONTAINERS               IMAGES                                                                      SELECTOR
tetragon   3         3         3       3            3           <none>          98s   export-stdout,tetragon   quay.io/cilium/hubble-export-stdout:v1.1.0,quay.io/cilium/tetragon:v1.5.0   app.kubernetes.io/instance=tetragon,app.kubernetes.io/name=tetragon

k -n kube-system get svc,ep tetragon
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/tetragon   ClusterIP   10.96.156.49   <none>        2112/TCP   105s
NAME                 ENDPOINTS                                                     AGE
endpoints/tetragon   192.168.10.100:2112,192.168.10.101:2112,192.168.10.102:2112   105s

k -n kube-system get svc,ep tetragon-operator-metrics
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/tetragon-operator-metrics   ClusterIP   10.96.169.67   <none>        2113/TCP   113s
NAME                                  ENDPOINTS           AGE
endpoints/tetragon-operator-metrics   172.20.2.239:2113   113s

k -n kube-system get pod -l app.kubernetes.io/part-of=tetragon -owide
NAME                                READY   STATUS    RESTARTS   AGE    IP               NODE      NOMINATED NODE   READINESS GATES
tetragon-ksnvb                      2/2     Running   0          2m1s   192.168.10.101   k8s-w1    <none>           <none>
tetragon-operator-58c6ddf88-hnskg   1/1     Running   0          2m1s   172.20.2.239     k8s-w2    <none>           <none>
tetragon-v8gcd                      2/2     Running   0          2m1s   192.168.10.100   k8s-ctr   <none>           <none>
tetragon-vh8ts                      2/2     Running   0          2m1s   192.168.10.102   k8s-w2    <none>           <none>

k -n kube-system get pod -l app.kubernetes.io/name=tetragon
NAME             READY   STATUS    RESTARTS   AGE
tetragon-ksnvb   2/2     Running   0          2m11s
tetragon-v8gcd   2/2     Running   0          2m11s
tetragon-vh8ts   2/2     Running   0          2m11s

kc -n kube-system describe pod -l app.kubernetes.io/name=tetragon
export-stdout:
    Container ID:  containerd://6b504f4e833d79b0a5e464f52f2e179382b3feae4023dd33640e93736bb25d65
    Image:         quay.io/cilium/hubble-export-stdout:v1.1.0
tetragon:
    Container ID:  containerd://9f66704cf4ee1bbcb68bba7ef32f27beff00863d1303b26c5bb91c71fe5001d3
    Image:         quay.io/cilium/tetragon:v1.5.0
```

### 1. Demo app 배포 및 tetragon 동작 확인
```sh
k create -f https://raw.githubusercontent.com/cilium/cilium/v1.18.1/examples/minikube/http-sw-app.yaml

k get pods

# xwing과 동일한 노드에 있는 파드 정보 가져오기
POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl get pod xwing -o jsonpath='{.spec.nodeName}'))
echo $POD
pod/tetragon-vh8ts

# 터비널 1
k exec -ti -n kube-system $POD -c tetragon -- tetra -h
k exec -ti -n kube-system $POD -c tetragon -- tetra getevents -o compact --pods xwing

# 터미널 2
### 명령어 1
k exec -ti xwing -- bash -c 'curl https://ebpf.io/applications/#tetragon'
🚀 process default/xwing /usr/bin/bash -c "curl https://ebpf.io/applications/#tetragon"
🚀 process default/xwing /usr/bin/curl https://ebpf.io/applications/#tetragon
💥 exit    default/xwing /usr/bin/curl https://ebpf.io/applications/#tetragon 0
### 명령어 2
k exec -ti xwing -- bash -c 'curl https://httpbin.org'
🚀 process default/xwing /usr/bin/bash -c "curl https://httpbin.org"
🚀 process default/xwing /usr/bin/curl https://httpbin.org
💥 exit    default/xwing /usr/bin/curl https://httpbin.org 0
### 명령어 3
k exec -ti xwing -- bash -c 'cat /etc/passwd'
🚀 process default/xwing /usr/bin/bash -c "cat /etc/passwd"
🚀 process default/xwing /usr/bin/cat /etc/passwd
💥 exit    default/xwing /usr/bin/cat /etc/passwd 0
```

### 2. 파일 액세스 모니터링
```sh
k apply -f https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/file_monitoring.yaml

k get tracingpolicy
NAME                       AGE
file-monitoring-filtered   13s

# 터미널 1
POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl get pod xwing -o jsonpath='{.spec.nodeName}'))
k exec -ti -n kube-system $POD -c tetragon -- tetra getevents -o compact --pods xwing

# 터미널 2
### 명령어 1
k exec -ti xwing -- bash -c 'cat /etc/shadow'
🚀 process default/xwing /usr/bin/bash -c "cat /etc/shadow"
🚀 process default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
💥 exit    default/xwing /usr/bin/cat /etc/shadow 0

### 명령어 2
k exec -ti xwing -- bash -c 'echo foo >> /etc/bar'
🚀 process default/xwing /usr/bin/bash -c "echo foo >> /etc/bar"
📝 write   default/xwing /usr/bin/bash /etc/bar
📝 write   default/xwing /usr/bin/bash /etc/bar
💥 exit    default/xwing /usr/bin/bash -c "echo foo >> /etc/bar" 0

# 정책 삭제
kubectl delete -f https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/file_monitoring.yaml
```

### 3. network monitoring
```sh
# pod의 CIDR의 경우 경우에 따라 수집 방법이 다르다.
# 1. Pod CIDR
export PODCIDR=`kubectl -n kube-system get pod -l component=kube-controller-manager -o yaml \
  | grep -i cluster-cidr \
  | cut -d= -f2`
echo $PODCIDR
10.244.0.0/16

# 2. 공식 문서 BASE
# 하지만 동작하지 않는 것으로 보인다. 설정에서도 - 10.244.0.0/24 10.244.1.0/24 10.244.2.0/24 형태로 값이 삽입된다.
export PODCIDR=`kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'`
echo $PODCIDR
10.244.0.0/24 10.244.1.0/24 10.244.2.0/24

# 3. ciliumn IPAM CIDR
export PODCIDR=`cilium config view | grep cluster-pool-ipv4-cidr | awk '{print $2}'`
echo $PODCIDR
172.20.0.0/16

# svc CIDR
export SERVICECIDR=$(kubectl describe pod -n kube-system -l component=kube-apiserver | awk -F= '/--service-cluster-ip-range/ {print $2; }')
echo $SERVICECIDR
10.96.0.0/16

wget https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/network_egress_cluster.yaml 
envsubst < network_egress_cluster.yaml | kubectl apply -f -

k get TracingPolicy
NAME                                                  AGE
monitor-network-activity-outside-cluster-cidr-range   16s

# 터미널 1
POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl get pod xwing -o jsonpath='{.spec.nodeName}'))

k exec -ti -n tetragon tetragon-zqmlw -c tetragon -- tetra getevents -o compact --pods xwing --processes curl

# 터미널 2
### 명령어 1
k exec -ti xwing -- bash -c 'curl https://ebpf.io/applications/#tetragon'
🚀 process default/xwing /usr/bin/curl https://ebpf.io/applications/#tetragon
🔌 connect default/xwing /usr/bin/curl tcp 172.20.2.59:43808 -> 172.67.71.235:443
💥 exit    default/xwing /usr/bin/curl https://ebpf.io/applications/#tetragon 0

### 명령어 2
k exec -ti xwing -- bash -c 'curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing'
🚀 process default/xwing /usr/bin/curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
💥 exit    default/xwing /usr/bin/curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing 0
Ship landed

# 리소스 삭제
envsubst < network_egress_cluster.yaml | kubectl delete -f -
```

### 4. 커널 수준에서 정책 제한 적용 설정
```sh
k apply -f https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/file_monitoring_enforce.yaml

k get tracingpolicynamespaced
NAME                       AGE
file-monitoring-filtered   3s

# 터미널 1
POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl get pod xwing -o jsonpath='{.spec.nodeName}'))
k exec -ti -n kube-system $POD -c tetragon -- tetra getevents -o compact --pods xwing

# 터미널 2
### 명령어 1
k exec -ti xwing -- bash -c 'cat /etc/shadow'
🚀 process default/xwing /usr/bin/bash -c "cat /etc/shadow"
🚀 process default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
📚 read    default/xwing /usr/bin/cat /etc/shadow
💥 exit    default/xwing /usr/bin/cat /etc/shadow SIGKILL
command terminated with exit code 137

### 명령어 2
k exec -ti xwing -- bash -c 'echo foo > /tmp/test.txt'
🚀 process default/xwing /usr/bin/bash -c "echo foo > /tmp/test.txt"
💥 exit    default/xwing /usr/bin/bash -c "echo foo > /tmp/test.txt" 0

k delete -f https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/file_monitoring_enforce.yaml
``` 