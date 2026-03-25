## 1.1 Multi-Pool
Multi-Pool IPAM은 사용자가 워크로드 어노테이션 또는 노드 레이블에 따라 IPAM 풀에서 PodCIDR를 할당한다. Pod 또는 네임스페이스에 `ipam.cilium.io/ip-pool` 어노테이션을 활용하여 pod의 ip 범위를 결정한다. 주의할 점은 생성 시에만 적용되며 기존 파드에 대한 어노테이션 변경 사항은 적용되지 않는다.

![](https://docs.cilium.io/en/stable/_images/multi-pool.png)

IPPool 결정 방법
- Pod 어노테이션을 통한 방법
- Namespace 어노테이션을 통한 방법
- 두 경우에 속하지 않은 경우 default Pool에서 IP를 할당받는다

Cilium Node CRD의 spec에 ipam.pools 항목이 추가된다
```sh
k get ciliumnodes.cilium.io
NAME      CILIUMINTERNALIP   INTERNALIP       AGE
k8s-ctr   172.20.1.138       192.168.10.100   9h
k8s-w1    172.20.0.11        192.168.10.101   9h

k describe ciliumnodes.cilium.io k8s-ctr  |grep -i ipam -A2
```

- spec.ipam.pools.requested
  - 해당 노드에 대한 IPAM POOL 목록이다. Cilium agnet가 노드에 요청된 POOL과 IP 주소 수를 소유하고 기록하며 cilium Operator 요청을 수행하기 위해 읽는다.
- spec.ipam.pools.allocated
  - 해당 노드에 할당된 CIDR 목록과 할당된 POOL이다. cilium Operator가 새 Pod CIDR를 추가하고 사용되지 않은 Pod CIDR를 제거한다.

클러스터 전체에 대한 IP POOL은 `CiliumPodIPPool CRD`을 통해 사용 및 관리된다.
```sh
k get ciliumpodippools.cilium.io 
```

- 운영 중에 새로운 IP Pool을 추가 및 확장이 가능하다.
- 기존에 정의된 IP Pool이 ciliumNode에서 사용 중인 경우 삭제되지 않을 수도 있다.
- Pool의 마스크 크기는 변경할 수 없고 모든 노드가 동일하다.
- 첫 번째 및 마지막 주소는 CiliumPodIPPool이 예약되어 할당 할당할수 없다. 하지만 주소가 3개 미만인 경우, (/31, /32, /127, /128)에는 이 제한이 없습니다.

**Multi Pool 활성화**
```sh
--set ipam.mode=multi-pool \
--set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs='{10.10.0.0/16}' \
--set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize=24 
```

**기존 CiliumPodIPPools 변경**
CiliumPodIPPools을 구성한 후에는 기본 POOL 범위를 변경할수 없다. 
1. 기본 IP POOL CIDR을 변경
2. 기본 IP POOL에 IPv6 CIDR 추가

기본 Pod CIDR를 새롭게 업데이트 하기 위해서는 다음과 같은 과정을 수행한다. 노드 중 일부를 그룹화하여 노드 그룹을 나눈다. 첫 번째로 작업을 수행한 노드 그룹 1과 이후 업데이트를 진행한 노드 그룹 2 그룹화한다.

1. helm의 `autoCreateCiliumPodIPPools` 값 변경
2. 기존 `CiliumPodIPPools CRD` 삭제 및 cilium operator 재시작 후 새 `CiliumPodIPPools` 생성
3. 노드 그룹 1에 배포된 파드 cordon 후 노드 그룹 2에게로 파드 추출
4. 노드 그룹 1 `ciliund Node CRD` 삭제 Cilium Agnet 재시작 노드 그룹 1 Uncordon
5. 노드 그룹 2에 배포된 파드 cordon 후 노드 그룹 1에게로 파드 할당함으로써 새 IP Pool에 속한 CIDR를 할당받는다.
6. 노드 그룹 2 `ciliund Node CRD` 삭제 Cilium Agnet 재시작 노드 그룹 2 Uncordon
7. (선택 사항) 클러스터 노드 간에 워크로드 재분배한다.

**Per-Node Default Pool**    
Cilium이 노드 IP Pool에 대해 레이블로 할당이 가능하다. 서로 다른 노드에 해당 데이터 센터의 서브넷에 맞는 IP가 필요한 다중 데이터 센터에 주로 사용된다. 

IPPool을 정의하고 `topology.kubernetes.io/zone` 레이블을 노드에 추가하여 각기 다른 다른 IP Pool를 사용할수 있다.

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: dc1-pool
spec:
  ipv4:
    cidrs:
      - 10.1.0.0/16
    maskSize: 24
---
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: dc2-pool
spec:
  ipv4:
    cidrs:
      - 10.2.0.0/16
    maskSize: 24
---
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  name: ip-pool-dc1
  namespace: kube-system
spec:
  defaults:
    ipam-default-ip-pool: dc1-pool
  nodeSelector:
    matchLabels:
      topology.kubernetes.io/zone: dc1
---
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  name: ip-pool-dc2
  namespace: kube-system
spec:
  defaults:
    ipam-default-ip-pool: dc2-pool
  nodeSelector:
    matchLabels:
      topology.kubernetes.io/zone: dc2
```

**Allocation Parameters**   
Cilium Agnet는 `ipam-multi-pool-pre-allocation` 옵션으로 각 풀에서 IP를 미리 할당할수 있다. 이때 키-값 맵으로 <Pool-name>=<PreAllocIps> 형식으로 구성된다. 

**Routing to Allocated PodCIDRs**   
CiliumPodIPPoool로 할당된 Pod CIDR는 `Cilium BGP Controle Plane`으로 전파되거나 `autoDirectNodeRoutes` helm 옵션으로 L2 네트워크의 노드 간 자동 라우팅을 활성화할 수 있다.

## 1.2 CRD by cilium multi-pool IPAM
여러 대역대의 IP POOl을 관리하는 `ciliumPodIPPool CRD`에 대한 튜토리얼이다. 하단의 옵션들이 필요하며 다음과 같은 [제약사항](https://docs.cilium.io/en/stable/network/concepts/ipam/multi-pool/#ipam-crd-multi-pool-limitations)이 존재한다.

```sh
helm upgrade --install cilium cilium/cilium -n kube-system \
  --set ipam.mode=multi-pool \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set ipv4NativeRoutingCIDR=10.0.0.0/8 \
  --set endpointRoutes.enabled=true \
  --set kubeProxyReplacement=true \
  --set bpf.masquerade=true \
  --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs='{10.10.0.0/16}' \
  --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize=27
```

**설치 검증**
```sh
cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

cilium config view |grep ipam
default-lb-service-ipam                           lbipam
enable-lb-ipam                                    true
ipam                                              multi-pool
ipam-cilium-node-update-rate                      15s
```

`CiliumpodIPPool CRD`가 파드 IP 풀에 대한 기본 값이 helm에서 정의한 값(`ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs`)과 동일한 CIDR로 생성되었는지 확인한다. 

```sh
k get ciliumpodippool default -o yaml

apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  creationTimestamp: "2025-08-02T14:48:26Z"
  generation: 1
  name: default
  resourceVersion: "44953"
  uid: 1ec1b03f-0253-4ade-85e2-4d360103ce0b
spec:
  ipv4:
    cidrs:
    - 10.10.0.0/16
    maskSize: 27
```

CiliumpodIPPool을 활용하여 추가 Pod IP Pool에 대해 정의한다.
```sh
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: mars
spec:
  ipv4:
    cidrs:
    - 10.20.0.0/16
    maskSize: 27
EOF
```

2개의 파드 풀이 존재하는지 확인
```sh
k get ciliumpodippools
NAME      AGE
default   6m46s
mars      5m54s
```

2개의 파드를 배포한다. 이때 하나는 `default` 풀에 할당하고 하나는 `mars` 풀에 할당한다. 이때 `default` 파드에 대해서는 어떠한 어노테이션도 필요없지만 `mars` 풀의 경우 Pod Spec에 `ipam.cilium.io/ip-pool: mars` 어노테이션을 추가해야 한다.

```sh
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-default
spec:
  selector:
    matchLabels:
      app: nginx-default
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx-default
    spec:
      containers:
      - name: nginx
        image: nginx:1.25.1
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-mars
spec:
  selector:
    matchLabels:
      app: nginx-mars
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx-mars
      annotations:
        ipam.cilium.io/ip-pool: mars
    spec:
      containers:
      - name: nginx
        image: nginx:1.25.1
        ports:
        - containerPort: 80
EOF
```

Pod IPv4 확인 
```sh
k get pods -o wide
nginx-default-6f4f9d7d57-89sqz   1/1     Running   0          15s   10.10.0.22     k8s-w1    <none>           <none>
nginx-mars-cd4d8ccb4-qzhjh       1/1     Running   0          15s   10.20.0.20     k8s-w1    <none>           <none>
```

서로 다른 pool에 속한 파드 간에 통신 테스트. k8s-w1 노드의 정보를 확인하면 ip pool에 대해 Allocated와 Requested이 추가된 것을 획인할 수 있다.
```sh
k exec pod/nginx-default-6f4f9d7d57-89sqz -- curl -s -o /dev/null -w "%{http_code}" 10.20.0.20
200

k describe ciliumnode k8s-w1 |grep -i ipam -A20
  Ipam:
    Pod CID Rs:
      172.20.0.0/24
    Pools:
      Allocated:
        Cidrs:
          10.10.0.0/27
        Pool:  default
        Cidrs:
          10.20.0.0/27
        Pool:  mars
      Requested:
        Needed:
          ipv4-addrs:  16
        Pool:          default
        Needed:
          ipv4-addrs:  1
        Pool:          mars
```

또한 `ipam.cilium.io/ipam-pool`는 네임스페이스에도 적용이 가능하다
```sh
k create namespace cilium-test
k annotate namespace cilium-test ipam.cilium.io/ip-pool=mars
```

cilium-test 네임스페이스에 생성되는 모든 파드들은 mars 풀에 해당하는 ip를 할당받는다. cilium 연결테스트를 수행한다. 연결테스트는 cilium-test 네임스페이스에서 실행된다. 연결 테스트를 완료하기 위해서는 최소 2개 이상의 노드를 가진 클러스터가 필요하다. 하단의 과정은 vm 스펙이 낮아 진행 속도가 낮아 스킵했다.

```sh
cilium connectivity test
```

cilium-test에 속한 파드들의 ip들이 mars pool에 속하는지 검증한다
```sh
k --namespace cilium-test get pods -o wide
```

[Multi-Pool](https://docs.cilium.io/en/stable/network/concepts/ipam/multi-pool/)   
[CRD](https://docs.cilium.io/en/stable/network/kubernetes/ipam-multi-pool/)