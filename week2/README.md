## [Cilium Study 1기] 2주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 2주차 스터디에 대한 정리 글입니다. 

```sh
# 전체 helm 정리 
helm install cilium cilium/cilium --version 1.17.6 --namespace kube-system \
--set k8sServiceHost=192.168.10.100 \
--set k8sServicePort=6443 \
--set ipam.mode="cluster-pool" \
--set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} \
--set ipv4NativeRoutingCIDR=172.20.0.0/16 \
--set routingMode=native \
--set autoDirectNodeRoutes=true \
--set endpointRoutes.enabled=true \
--set kubeProxyReplacement=true \
--set bpf.masquerade=true \
--set installNoConntrackIptablesRules=true \
--set endpointHealthChecking.enabled=false \
--set healthChecking=false \
--set hubble.enabled=false \
--set operator.replicas=1 \
--set debug.enabled=true \
--set hubble.enabled=true \
--set hubble.relay.enabled=true \
--set hubble.ui.enabled=true \
--set hubble.ui.service.type=NodePort \
--set hubble.ui.service.nodePort=31234 \
--set hubble.export.static.enabled=true \
--set hubble.export.static.filePath=/var/run/cilium/hubble/events.log \
--set prometheus.enabled=true \
--set operator.prometheus.enabled=true \
--set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"
```

### Hubble
- Hubble API 
  - 작업을 수행하는 노드(로컬)에 대한 hubble api에 액세스한다. 정확히는 cilium agent이다. hubble cli가 로컬 유닉스 도메인 소켓으로 제공되는 hubble api에 쿼리할수 있다.
- Hubble Relay
  - 클러스터 전체에 대한 네트워크 가시성을 제공한다. 기존의 hubble cli를 hubble-relay에 요청을 보내거나 hubble-ui를 통해 네트워크 가시성을 조회할수 있다.
- Hubble Peer

> hubble-relay:4425 -> hubble-peer:443 -> 모든 노드의 hubble:4244 

## Hubble 배포 및 설정 조회
```sh
helm repo add cilium https://helm.cilium.io/ 
helm repo update 

# endpointHealthChecking과 healthChecking 옵션이 추가로 비활성화 되었다.
# 헬스 체크로 인해 10대의 노드를 넘기는 경우 최적화를 위해 비활성화한다.
helm install cilium cilium/cilium --version 1.17.6 --namespace kube-system \
--set k8sServiceHost=192.168.10.100 \
--set k8sServicePort=6443 \
--set ipam.mode="cluster-pool" \
--set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} \
--set ipv4NativeRoutingCIDR=172.20.0.0/16 \
--set routingMode=native \
--set autoDirectNodeRoutes=true \
--set endpointRoutes.enabled=true \
--set kubeProxyReplacement=true \
--set bpf.masquerade=true \
--set installNoConntrackIptablesRules=true \
--set endpointHealthChecking.enabled=false \ 
--set healthChecking=false \ 
--set hubble.enabled=false \
--set operator.replicas=1 \
--set debug.enabled=true \

# cilium 상태 조회
# hubble-relay가 실행중이지 않은 것을 확인할 수 있다.
cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 1
                       clustermesh-apiserver
                       hubble-relay

# Hubble 설정 조회
cilium config view | grep -i hubble
enable-hubble false

# hubble 활성화 및 hubble flow 파일 저장
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
--set hubble.enabled=true \
--set hubble.relay.enabled=true \
--set hubble.ui.enabled=true \
--set hubble.ui.service.type=NodePort \
--set hubble.ui.service.nodePort=31234 \
--set hubble.export.static.enabled=true \
--set hubble.export.static.filePath=/var/run/cilium/hubble/events.log \
--set prometheus.enabled=true \
--set operator.prometheus.enabled=true \
--set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"

# 또는 cli를 통해 hubble 활성화가 가능하다
cilium hubble enable
cilium hubble enable --ui

# hubble-ui와 relay가 활성화 됐다.
cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             hubble-relay             Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-ui                Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       hubble-relay             Running: 1
                       hubble-ui                Running: 1

cilium config view | grep -i hubble
enable-hubble                                     true
enable-hubble-open-metrics                        true
hubble-disable-tls                                false
hubble-export-allowlist
hubble-export-denylist
hubble-export-fieldmask
hubble-export-file-max-backups                    5
hubble-export-file-max-size-mb                    10
hubble-export-file-path                           /var/run/cilium/hubble/events.log
hubble-listen-address                             :4244
hubble-metrics                                    dns drop tcp flow port-distribution icmp httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction
hubble-metrics-server                             :9965
hubble-metrics-server-enable-tls                  false
hubble-socket-path                                /var/run/cilium/hubble.sock
hubble-tls-cert-file                              /var/lib/cilium/tls/hubble/server.crt
hubble-tls-client-ca-files                        /var/lib/cilium/tls/hubble/client-ca.crt
hubble-tls-key-file                               /var/lib/cilium/tls/hubble/server.key


# 기본적으로 cilium이 생성한 ca 값과 tls 인증서들이다.
kubectl get secret -n kube-system | grep -iE 'cilium-ca|hubble'
cilium-ca                      Opaque                          2      3m26s
hubble-relay-client-certs      kubernetes.io/tls               3      3m26s
hubble-server-certs            kubernetes.io/tls               3      3m26s


# hubble은 4244 포트로 통신하는 반면, hubble-relay는 4245 포트로 통신한다.
kc get svc,ep -n kube-system hubble-relay
NAME                   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/hubble-relay   ClusterIP   10.96.161.94   <none>        80/TCP    6m11s

NAME                     ENDPOINTS           AGE
endpoints/hubble-relay   172.20.2.132:4245   6m11s


# hubble-relay가 hubble-peer(:443)를 통해 클러스터의 모든 노드의 :4244에 요청을 가져온디
kubectl get cm -n kube-system
hubble-relay-config                                    1      8m31s

kubectl describe cm -n kube-system hubble-relay-config
cluster-name: default
peer-service: "hubble-peer.kube-system.svc.cluster.local.:443"
listen-address: :4245


# hubble-peer에 대한 서비스(:443)과 엔드포인트 값으로든 노드의 4244으로 설정된 것을 조회할수 있다.
kubectl get svc,ep -n kube-system hubble-peer
service/hubble-peer   ClusterIP   10.96.60.99   <none>        443/TCP   9m22s
endpoints/hubble-peer   192.168.10.100:4244,192.168.10.101:4244,192.168.10.102:4244   9m22s


# Hubble CLI 설치 
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
which hubble


# hubble status를 보내도 에러가 발생한다. 왜냐하면 로컬에는 4245포트로 리스닝 중인 서비스가 없기 떄문이다.
# 따라서 로컬에서도 hubble-relay 통신이 가능하도록 다음 명령어를 실행한다. 
hubble status
failed getting status: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp 127.0.0.1:4245: connect: connection refused"

cilium hubble port-forward&
Hubble Relay is available at 127.0.0.1:4245

# 모든 노드에 대한 hubble 상태를 조회할수 있다.
hubble status
Healthcheck (via localhost:4245): Ok
Current/Max Flows: 10,306/12,285 (83.89%)
Flows/s: 36.20
Connected Nodes: 3/3
```

https://docs.cilium.io/en/stable/observability/hubble/setup/

## Sample Application을 통한 L3 cilium Network Policy 적용 
![](https://docs.cilium.io/en/stable/_images/cilium_http_gsg.png)

```sh
# cilium 단축키 지정 
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

# 샘플 APP 배포
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/http-sw-app.yaml

# 배포 상태 조회 
kubectl get pods,svc
NAME                            READY   STATUS    RESTARTS   AGE
pod/curl-pod                    1/1     Running   0          8h
pod/deathstar-8c4c77fb7-knv2j   1/1     Running   0          10m
pod/deathstar-8c4c77fb7-rfh6r   1/1     Running   0          14m
pod/tiefighter                  1/1     Running   0          111s
pod/xwing                       1/1     Running   0          15m
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/deathstar    ClusterIP   10.96.31.96   <none>        80/TCP    15m
service/kubernetes   ClusterIP   10.96.0.1     <none>        443/TCP   11h

k get ciliumendpoints.cilium.io
NAME                        SECURITY IDENTITY   ENDPOINT STATE   IPV4           IPV6
curl-pod                    8663                ready            172.20.0.28
deathstar-8c4c77fb7-knv2j   63642               ready            172.20.1.75
deathstar-8c4c77fb7-rfh6r   63642               ready            172.20.1.6
tiefighter                  17788               ready            172.20.2.6
xwing                       61965               ready            172.20.1.199

# 서큐리티 아이덴티티로 보안에 대한 정책을 구성한다
k get ciliumidentities.cilium.io
NAME    NAMESPACE      AGE
17788   default        13m
18396   kube-system    5h31m
18646   prometheus     10h
22347   loki           54m
23696   prometheus     10h
2495    loki           51m
30797   loki           50m
32713   kube-system    11h
33074   prometheus     10h
4527    prometheus     10h
48377   kube-system    11h
51655   cert-manager   5h3m
58780   prometheus     10h
61965   default        14m
63642   default        14m
7050    cert-manager   5h3m
748     cert-manager   5h3m
8303    kube-system    11h
8663    default        8h

# 중요한 것은 각 노드에서 cilium 엔드포인트에 대한 어떠한 ingress, egress 정책이 없다는 것이다. 즉 트래픽에 대한 어떠한 차단도 수행하지 않는다. 
kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium endpoint list
c0 endpoint list
c1 endpoint list
c2 endpoint list

ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                                  IPv6   IPv4           STATUS
           ENFORCEMENT        ENFORCEMENT
26         Disabled           Disabled          63642      k8s:app.kubernetes.io/name=deathstar                                                172.20.1.6     ready
                                                           k8s:class=deathstar
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
                                                           k8s:org=empire
105        Disabled           Disabled          1          reserved:host                                                                                      ready
1091       Disabled           Disabled          61965      k8s:app.kubernetes.io/name=xwing                                                    172.20.1.199   ready
                                                           k8s:class=xwing
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
                                                           k8s:org=alliance
222        Disabled           Disabled          17788      k8s:app.kubernetes.io/name=tiefighter                                               172.20.2.6     ready
                                                           k8s:class=tiefighter
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
                                                           k8s:org=empire
                                                
# 트래픽 여부 확인
# xwing -> 데스스타, tiefighter -> 데스스타 두 파드 모두 정상적으로 요청이 전송된다.
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

# cilium에서는 엔드포인트와는 관계없이 라벨로 보안 정책을 정의한다.
# CiliumNetworkPolicies는 "endpointSelector"를 사용하여 포드 레이블에서 일치하여 정책이 적용되는 소스 및 대상을 식별한다
# TCP 포트 80에서 레이블(org=empire, class=deathstar)이 있는 모든 파드에서 레이블(org=empire, class=deathstar)이 있는 데스스타 파드로 전송된 트래픽을 화이트리스트에 추가한다.
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/sw_l3_l4_policy.yaml

# 성공
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

# 실패
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing

# hubble-ui를 통해서도 패킷이 dropped된 것을 찾을 수가 있다.

# 이전과는 다르게 인그레스에 대한 정책이 활성화 되어있다.
c1 endpoint list
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                                  IPv6   IPv4           STATUS
2284       Enabled            Disabled          63642      k8s:app.kubernetes.io/name=deathstar                                                172.20.1.75    ready
                                                           k8s:class=deathstar
                                                           k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
                                                           k8s:io.cilium.k8s.policy.cluster=default
                                                           k8s:io.cilium.k8s.policy.serviceaccount=default
                                                           k8s:io.kubernetes.pod.namespace=default
                                                           k8s:org=empire

# ciliumidentities 조회
k get ciliumidentities.cilium.io 63642
NAME    NAMESPACE   AGE
63642   default     30m

k describe ciliumidentities.cilium.io 63642
Name:         63642
Labels:       app.kubernetes.io/name=deathstar
              class=deathstar
              io.cilium.k8s.policy.cluster=default
              io.cilium.k8s.policy.serviceaccount=default
              io.kubernetes.pod.namespace=default
              org=empire
Kind:         CiliumIdentity
Security - Labels:
  k8s:app.kubernetes.io/name:                                      deathstar
  k8s:class:                                                       deathstar
  k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name:  default
  k8s:io.cilium.k8s.policy.cluster:                                default
  k8s:io.cilium.k8s.policy.serviceaccount:                         default
  k8s:io.kubernetes.pod.namespace:                                 default
  k8s:org:                                                         empire
Events:                                                            <none>

kubectl get cnp
NAME    AGE
rule1   2m

# 구체적인 정보 조회
kubectl describe cnp rule1
...
Endpoint Selector:
    Match Labels:
      Class:  deathstar
      Org:    empire
  Ingress:
    From Endpoints:
      Match Labels:
        Org:  empire
    To Ports:
      Ports:
        Port:      80
        Protocol:  TCP
```

## L7 cilium Network Policy 적용 
![](https://docs.cilium.io/en/stable/_images/cilium_http_l3_l4_l7_gsg.png)

```sh
# tiefighter가 도달할 수 있는 URL을 제한할 수 있습니다.
# tiefighter가 POST /v1/request-landing API 호출만 수행하도록 제한하고 다른 모든 호출(PUT /v1/exhaust-port 포함)을 허용하지 않는 정책이다.
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/sw_l3_l4_l7_policy.yaml

kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
Access denied

# 해당 규칙은 ID 인식 규칙을 기반으로 하여 레이블이 없는 Pod의 트래픽 org=empire는 시간 초과된다.
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing

# L7 정책 조회
kubectl describe ciliumnetworkpolicies
c1 policy get

# 라소스 삭제
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/http-sw-app.yaml
kubectl delete cnp rule1
```
https://docs.cilium.io/en/stable/gettingstarted/demo/


## L7 Protocol Visibility
기본적으로 datapath state는 l3/l4 패킷에 대한 가시성만 제공. L7 프로토콜에 대한 가시성을 활성화 하기위해서는 L7 규칙을 지정하는 CiliumNetworkPolicy을 생성해야 한다.

```sh
# 샘플 앱 배포 
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

# L7 cnp 생성
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "l7-visibility"
spec:
  endpointSelector:
    matchLabels:
      "k8s:io.kubernetes.pod.namespace": default  # default 네임스페이스 안의 모든 Pod에 대해 egress 정책이 적용
  egress:
  - toPorts:
    - ports:
      - port: "53"
        protocol: ANY  # TCP, UDP 둘 다 허용
      rules:
        dns:
        - matchPattern: "*"  # 모든 도메인 조회 허용, L7 가시성 활성화
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": default
    toPorts:
    - ports:
      - port: "80"  # default 다른 파드의 HTTP TCP 80 요청 허용
        protocol: TCP
      - port: "8080"  # default 다른 파드의 HTTP TCP 8080 요청 허용
        protocol: TCP
      rules:
        http: [{}]  # 모든 HTTP 요청을 허용, L7 가시성 활성화
EOF

kubectl get cnp -o yaml

kubectl exec -it curl-pod -- curl -s webpod
Hostname: webpod-697b545f57-6r8dk
IP: 127.0.0.1
IP: ::1
IP: 172.20.2.39
IP: fe80::e890:24ff:fe7a:edc6
RemoteAddr: 172.20.0.28:56004
GET / HTTP/1.1
Host: webpod
User-Agent: curl/8.14.1
Accept: */*
X-Envoy-Expected-Rq-Timeout-Ms: 3600000
X-Envoy-Internal: true
X-Forwarded-Proto: http
X-Request-Id: 6721efc1-27e2-4e15-842f-b9f4a6abc132

# 정말 좋다. curl-pod에서 webpod까지의 네트워크 요청 과정을 한눈에 알아볼 수 있다. 
hubble observe -f -t l7 -o compact
Jul 26 17:21:44.256: default/curl-pod:43565 (ID:8663) -> kube-system/coredns-674b8bbfcf-mvbdg:53 (ID:8303) dns-request proxy FORWARDED (DNS Query webpod.default.svc.cluster.local. AAAA)
Jul 26 17:21:44.258: default/curl-pod:43565 (ID:8663) -> kube-system/coredns-674b8bbfcf-mvbdg:53 (ID:8303) dns-request proxy FORWARDED (DNS Query webpod.default.svc.cluster.local. A)
Jul 26 17:21:44.258: default/curl-pod:43565 (ID:8663) <- kube-system/coredns-674b8bbfcf-mvbdg:53 (ID:8303) dns-response proxy FORWARDED (DNS Answer  TTL: 4294967295 (Proxy webpod.default.svc.cluster.local. AAAA))
Jul 26 17:21:44.260: default/curl-pod:43565 (ID:8663) <- kube-system/coredns-674b8bbfcf-mvbdg:53 (ID:8303) dns-response proxy FORWARDED (DNS Answer "10.96.129.155" TTL: 30 (Proxy webpod.default.svc.cluster.local. A))
Jul 26 17:21:44.262: default/curl-pod:52110 (ID:8663) -> default/webpod-697b545f57-6r8dk:80 (ID:17245) http-request FORWARDED (HTTP/1.1 GET http://webpod/)
Jul 26 17:21:44.266: default/curl-pod:52110 (ID:8663) <- default/webpod-697b545f57-6r8dk:80 (ID:17245) http-response FORWARDED (HTTP/1.1 200 3ms (GET http://webpod/))

```

하지만 이러한 허블도 단점이 존재한다. 사용자가 민간함 정보에 대해서 전부 필터링을 걸어줘야 한다는 점이다. 
```sh
# 예를 들어 쿼리스트링에 데이터를 넣었을 때 허블에서도 조회가 가능하다.
kubectl exec -it curl-pod -- sh -c 'curl -s webpod/?user_id=1234'

hubble observe -f -t l7 -o compact
Jul 26 17:25:32.272: default/curl-pod:55958 (ID:8663) -> default/webpod-697b545f57-4r8tw:80 (ID:17245) http-request FORWARDED (HTTP/1.1 GET http://webpod/?user_id=1234)
Jul 26 17:25:32.277: default/curl-pod:55958 (ID:8663) <- default/webpod-697b545f57-4r8tw:80 (ID:17245) http-response FORWARDED (HTTP/1.1 200 5ms (GET http://webpod/?user_id=1234))

# URL 쿼리 부분 제거 
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set extraArgs="{--hubble-redact-enabled,--hubble-redact-http-urlquery}"

# 쿼리 부분이 지워진 것을 확인할수 있다.
kubectl exec -it curl-pod -- sh -c 'curl -s webpod/?user_id=1234'

hubble observe -f -t l7 -o compact
Jul 26 17:25:35.102: default/curl-pod:52110 (ID:8663) -> default/webpod-697b545f57-6r8dk:80 (ID:17245) http-request FORWARDED (HTTP/1.1 GET http://webpod/)
Jul 26 17:25:35.105: default/curl-pod:52110 (ID:8663) <- default/webpod-697b545f57-6r8dk:80 (ID:17245) http-response FORWARDED (HTTP/1.1 200 3ms (GET http://webpod/))
```


https://github.com/cilium/cilium/blob/v1.17.6/api/v1/flow/flow.proto#L518