## 3. Local Redirect Policy 실습 정리(미완)

LRP란 파드, IP, k8s 서비스로 향하는 파드 트랙픽을 노드 내에 파드로 로컬 리다이렉하는 cilium 정책이자 `CiliumLocalRedirectPolicy CRD` 이다. 간단하게 이야기하자면 http 301과 같은 의미로 보인다. 이때 파드의 네임스페이스는 정책의 네임스페이스와 동일해야 한다. 

지원 정책 유형 
1. k8s 서비스인 경우 CluterIP 타입의 서비스와 `ServiceMatcher` 유형을 사용한다.
2. 나머지의 경우에는 `AddressMatcher` 유형을 사용한다. 


```sh
#
helm uninstall -n kube-system cilium

#
iptables-save | grep -v KUBE | grep -v CILIUM | iptables-restore
iptables-save

sshpass -p 'vagrant' ssh vagrant@k8s-w1 "sudo iptables-save | grep -v KUBE | grep -v CILIUM | sudo iptables-restore"
sshpass -p 'vagrant' ssh vagrant@k8s-w1 sudo iptables-save

#
helm install cilium cilium/cilium --version 1.17.6 --namespace kube-system \
--set k8sServiceHost=192.168.10.100 --set k8sServicePort=6443 \
--set ipam.mode="cluster-pool" --set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} --set ipv4NativeRoutingCIDR=172.20.0.0/16 \
--set routingMode=native --set autoDirectNodeRoutes=true --set endpointRoutes.enabled=true \
--set kubeProxyReplacement=true --set bpf.masquerade=true --set installNoConntrackIptablesRules=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set hubble.enabled=true --set hubble.relay.enabled=true --set hubble.ui.enabled=true \
--set hubble.ui.service.type=NodePort --set hubble.ui.service.nodePort=30003 \
--set prometheus.enabled=true --set operator.prometheus.enabled=true --set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
--set operator.replicas=1 --set debug.enabled=true --set cleanBpfState=true --set cleanState=true

#
k9s → pod → 0 (all) 
```



```sh
helm repo add cilium https://helm.cilium.io/

helm upgrade cilium cilium/cilium --version 1.18.0 \
  --namespace kube-system \
  --reuse-values \
  --set kubeProxyReplacement=true \
  --set socketLB.hostNamespaceOnly=true \
  --set localRedirectPolicies.enabled=true

k rollout restart deploy cilium-operator -n kube-system
k rollout restart ds cilium -n kube-system

k -n kube-system get pods -l k8s-app=cilium
NAME           READY   STATUS    RESTARTS   AGE
cilium-5ngzd   1/1     Running   0          3m19s

k -n kube-system get pods -l name=cilium-operator
NAME                               READY   STATUS    RESTARTS   AGE
cilium-operator-544b4d5cdd-qxvpv   1/1     Running   0          3m19s

k get crds
NAME                              CREATED AT
[...]
ciliumlocalredirectpolicies.cilium.io              2020-08-24T05:31:47Z

# 백엔드 파드 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: lrp-pod
  labels:
    app: proxy
spec:
  containers:
    - name: lrp-pod
      image: nginx
      ports:
        - containerPort: 80
          name: tcp
          protocol: TCP
EOF

k get pods | grep lrp-pod
lrp-pod                      1/1     Running   0          46s


k create -f https://raw.githubusercontent.com/cilium/cilium/1.18.0/examples/kubernetes-dns/dns-sw-app.yaml
k wait pod/mediabot --for=condition=Ready
k get pods
NAME                             READY   STATUS    RESTARTS   AGE
pod/mediabot                     1/1     Running   0          14s

kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.0/examples/kubernetes-local-redirect/lrp-addrmatcher.yaml

k get ciliumlocalredirectpolicies | grep lrp-addr
NAME           AGE
lrp-addr       20h

k describe pod lrp-pod  | grep 'IP:'
IP:           10.16.70.187


k exec -it -n kube-system cilium-5ngzd -- cilium-dbg service list
ID   Frontend               Service Type       Backend
[...]
4    172.20.0.51:80         LocalRedirect      1 => 10.16.70.187:80

k exec mediabot -- curl -I -s http://169.254.169.254:8080/index.html
HTTP/1.1 200 OK
Server: nginx/1.19.2
Date: Fri, 28 Aug 2020 01:33:34 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 11 Aug 2020 14:50:35 GMT
Connection: keep-alive
ETag: "5f32b03b-264"
Accept-Ranges: bytes

tcpdump -i any -n port 80


localRedirectPolicies:
  enabled: true
  addressMatchCIDRs:
      - 169.254.169.254/32

apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app: MyApp
  ports:
    - name: tcp
      protocol: TCP
      port: 80


kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.0/examples/kubernetes-local-redirect/k8s-svc.yaml

kubectl get service | grep 'my-service'

kubectl exec -it -n kube-system ds/cilium -- cilium-dbg service list


apiVersion: "cilium.io/v2"
kind: CiliumLocalRedirectPolicy
metadata:
  name: "lrp-svc"
spec:
  redirectFrontend:
    serviceMatcher:
      serviceName: my-service
      namespace: default
  redirectBackend:
    localEndpointSelector:
      matchLabels:
        app: proxy
    toPorts:
      - port: "80"
        protocol: TCP

kubectl get ciliumlocalredirectpolicies | grep svc

kubectl exec -it -n kube-system cilium-5ngzd -- cilium-dbg service list

kubectl exec mediabot -- curl -I -s http://172.20.0.51/index.html

kubectl describe pod lrp-pod  | grep 'IP:'

sudo tcpdump -i any -n port 80
```

https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/