## 4. L2 Pod Announcements 설정 및 동작 확인(실패)
L2 service announcements 비슷한 개념으로 pod ip에 대해서 grap로 주소를 응답하는 것으로 이해했다. 노드의 네트워크 인터페이스에 모든 파드의 ip에 대해서 arp 응답한다.

만일 파드의 IP로 요청을 보내면 k8s node의 mac 주소를 응답하고 요청을 보내게 될줄 알았는데 보내지지 않는다. 공식 문서에서만 자료가 있고 이외에는 자료도 없어서 어떤 경우에 사용해야 하는지 감도 잡히지 않는다. 

```sh
helm upgrade cilium cilium/cilium --version 1.18.0 \
   --namespace kube-system \
   --reuse-values \
   --set l2podAnnouncements.enabled=true \
   --set l2podAnnouncements.interfacePattern='^(eth0|eth1)$'

k rollout restart -n kube-system ds/cilium

k get pod -o wide
curl-pod                        1/1     Running   1 (34h ago)   2d10h   172.20.0.102   k8s-ctr   <none>           <none>
webpod-697b545f57-2nk8p         1/1     Running   0             2d10h   172.20.2.77    k8s-w0    <none>           <none>
webpod-697b545f57-kf46p         1/1     Running   0             2d10h   172.20.1.219   k8s-w1    <none>           <none>
webpod-697b545f57-rpxqc         1/1     Running   1 (34h ago)   2d10h   172.20.0.158   k8s-ctr   <none>           <none>

# Router 
curl -v 172.20.2.77

# 시도 
# ctr 노드에 전달하기 설정. eth1, eth0 시도
sudo ip route add 172.20.0.0/24 via eth1
sudo ip route add 172.20.0.0/24 via eth0

arp
Address                  HWtype  HWaddress           Flags Mask            Iface
172.20.0.130                     (incomplete)                              eth0
172.20.0.130                     (incomplete)                              eth1

ip neigh show | grep 172.20
172.20.0.130 dev eth0 FAILED
172.20.0.130 dev eth1 FAILED

cilium config view |grep pod
enable-l2-pod-announcements                       true
k8s-require-ipv4-pod-cidr                         false
k8s-require-ipv6-pod-cidr                         false
l2-pod-announcements-interface-pattern            ^(eth0|eth1)$
```
https://docs.cilium.io/en/stable/network/l2-announcements/#l2-pod-announcements