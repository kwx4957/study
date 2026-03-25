## 1. Router에 Static Route 설정 
다른 대역대의 클러스터 노드내에서 통신이 안되는 이유 패킷을 거쳐가는 Router 역할을 담당하는 서버에 Pod CIDR에 대한 정보가 없기 때문이다. 이중 정적으로 설정하는 방법으로 접근하자.

해결 방안 2가지 
- 라우팅 정적 설정
- 오버레이 네트워크 활용 

Router 서버의 route 테이블 조회 
```sh
ip -c route s 
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.1.0/24 dev loop1 proto kernel scope link src 10.10.1.200
10.10.2.0/24 dev loop2 proto kernel scope link src 10.10.2.200
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.200
192.168.20.0/24 dev eth2 proto kernel scope link src 192.168.20.200
```

Router 서버에 정적 라우팅 설정
```sh
# 오버레이 네트워크의 경우에는 원본 패킷을 캡슐화해서 보내게된다. SNAT 처리하게됨 
# 여기서 172.20.0.0/24는 ciliumnode가 할당받은 Pod CIDR로 해당하는 요청은 192.168.10.100에 전달하게 된다.
sudo ip route add 172.20.0.0/24 via 192.168.10.100
sudo ip route add 172.20.1.0/24 via 192.168.10.101
sudo ip route add 172.20.2.0/24 via 192.168.20.100

ip -c route s
default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev eth0 proto kernel scope link src 10.0.2.15 metric 100
10.0.2.2 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.0.2.3 dev eth0 proto dhcp scope link src 10.0.2.15 metric 100
10.10.1.0/24 dev loop1 proto kernel scope link src 10.10.1.200
10.10.2.0/24 dev loop2 proto kernel scope link src 10.10.2.200
172.20.0.0/24 via 192.168.10.100 dev eth1
172.20.2.0/24 via 192.168.20.100 dev eth2
192.168.10.0/24 dev eth1 proto kernel scope link src 192.168.10.200
192.168.20.0/24 dev eth2 proto kernel scope link src 192.168.20.200
```

k8s 클러스터 간에 통신 검증
```sh 
k exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done
```

Router 
```sh
ip -c addr s |grep 192
    inet 192.168.10.200/24 brd 192.168.10.255 scope global eth1
    inet 192.168.20.200/24 brd 192.168.20.255 scope global eth2

# eth1으로 요청이 들어와서 eh2으로 요청이 나가는 것을 획안할 수 있다.
tcpdump -i any icmp -nn
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
14:28:39.388606 eth1  In  IP 172.20.0.53 > 172.20.2.77: ICMP echo request, id 189, seq 1, length 64
14:28:39.388616 eth2  Out IP 172.20.0.53 > 172.20.2.77: ICMP echo request, id 189, seq 1, length 64
14:28:39.389079 eth2  In  IP 172.20.2.77 > 172.20.0.53: ICMP echo reply, id 189, seq 1, length 64
14:28:39.389082 eth1  Out IP 172.20.2.77 > 172.20.0.53: ICMP echo reply, id 189, seq 1, length 64
```

Route 삭제 
```sh
sudo ip route del 172.20.0.0/24
sudo ip route del 172.20.1.0/24
sudo ip route del 172.20.2.0/24
```