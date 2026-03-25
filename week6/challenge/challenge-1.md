- `도전과제1-2` Ingress gRPC Example : arm64 CPU 미지원 - [Docs](https://docs.cilium.io/en/stable/network/servicemesh/grpc/)
- `도전과제1-3` **Defaults certificate** for Ingresses - [Docs](https://docs.cilium.io/en/stable/network/servicemesh/tls-default-certificate/)

## 도전과제1-1 [Ingress Host network mode](https://docs.cilium.io/en/stable/network/servicemesh/ingress/#host-network-mode)
envoy가 호스트 네트워크를 사용하게끔 한다. 이 경우는 개발 환경 또는 클러스터 외부 LB 환경 같은 LB를 사용할수 없는 환경에 적합하다. LB 또는 NodePort와는 상호 배타적이다.

```sh
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm upgrade -i  cilium cilium/cilium --version 1.18.1 --namespace kube-system \
    --set k8sServiceHost=192.168.10.100 --set k8sServicePort=6443 \
    --set ipam.mode="cluster-pool" --set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} --set ipv4NativeRoutingCIDR=172.20.0.0/16 \
    --set routingMode=native --set autoDirectNodeRoutes=true --set endpointRoutes.enabled=true --set directRoutingSkipUnreachable=true \
    --set kubeProxyReplacement=true --set bpf.masquerade=true --set installNoConntrackIptablesRules=true \
    --set endpointHealthChecking.enabled=false --set healthChecking=false \
    --set hubble.enabled=true --set hubble.relay.enabled=true --set hubble.ui.enabled=true \
    --set hubble.ui.service.type=NodePort --set hubble.ui.service.nodePort=30003 \
    --set prometheus.enabled=true --set operator.prometheus.enabled=true --set hubble.metrics.enableOpenMetrics=true \
    --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
    --set ingressController.enabled=true --set ingressController.loadbalancerMode=shared --set loadBalancer.l7.backend=envoy \
    --set localRedirectPolicy=true --set l2announcements.enabled=true \
    --set operator.replicas=1 --set debug.enabled=true \
    --set ingressController.hostNetwork.enabled=true

k -n kube-system rollout restart ds/cilium-envoy

cilium status --wait

# Shared 모드의 인그레스의 기본 포트는 8080포트이다
cilium config view |grep host
controller-group-metrics                          write-cni-file sync-host-ips sync-lb-maps-with-k8s-services
ingress-hostnetwork-enabled                       true
ingress-hostnetwork-nodelabelselector
ingress-hostnetwork-shared-listener-port          8080
procfs                                            /host/proc
tofqdns-endpoint-max-ip-per-hostname              1000
write-cni-conf-when-ready                         /host/etc/cni/net.d/05-cilium.conflist

ss -tnlp | grep 8080
LISTEN 0      4096          0.0.0.0:8080       0.0.0.0:*    users:(("cilium-envoy",pid=48945,fd=49))
LISTEN 0      4096          0.0.0.0:8080       0.0.0.0:*    users:(("cilium-envoy",pid=48945,fd=48))

# Router 
curl -v 192.168.10.100:8080
```
