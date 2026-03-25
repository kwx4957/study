## 5. LB 타입의 Service에 NodePort 비활성화 설정

기존의 서비스를 변경하더라도 clusterIP와 NodePort를 할당받아서 변경되지 않는다. 공식 문서에서는 `service.cilium.io/type` 설정을 지정하면 지정된 유형의 서비스만 생성된다고 적혀있으나, 막상 조회하면 clusterIP도 할당받은 것을 볼수 있다.

```sh
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: netshoot-web3
  annotations:
    service.cilium.io/type: LoadBalancer
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
  allocateLoadBalancerNodePorts: false
EOF

k get svc,ep
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
service/netshoot-web    LoadBalancer   10.96.56.141    192.168.10.215   80:30412/TCP     34h
service/netshoot-web2   LoadBalancer   10.96.225.170   192.168.10.215   8080:30983/TCP   161m
service/netshoot-web3   LoadBalancer   10.96.141.85    192.168.10.212   80/TCP           4m14s
service/webpod          LoadBalancer   10.96.48.145    192.168.10.211   80:32050/TCP     2d10h

NAME                      ENDPOINTS                                              AGE
endpoints/netshoot-web    172.20.0.36:8080,172.20.1.117:8080,172.20.2.230:8080   34h
endpoints/netshoot-web2   172.20.0.36:8080,172.20.1.117:8080,172.20.2.230:8080   161m
endpoints/netshoot-web3   172.20.0.36:8080,172.20.1.117:8080,172.20.2.230:8080   4m14s
endpoints/webpod          172.20.0.158:80,172.20.1.219:80,172.20.2.77:80         2d10h
```

Router 접근 확인
```sh
curl -s 192.168.10.212
OK from netshoot-web-5c59d94bd4-j5hzw
```

https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#selective-service-type-exposure