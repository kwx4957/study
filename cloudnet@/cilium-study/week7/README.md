## [Cilium Study 1기] 7주차 정리
> 본 내용은 CloudNet@ Cilium Study 1기 7주차 스터디에 대한 정리 글입니다. 

### Kind 배포
```sh
# 프로메테우스가 k8s 컨트롤 플레인 관련 컴포넌트에 대한 메트릭을 수집할 수 있도록 하는 설정
kind create cluster --name myk8s --image kindest/node:v1.33.2 --config kind-config.yaml

# kube-ops-view 배포
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/
helm repo update 
helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 \
  --set service.main.type=NodePort,service.main.ports.http.nodePort=30003 \
  --set env.TZ="Asia/Seoul" --namespace kube-system

open http://localhost:30003/#scale=1.5
open http://localhost:30003/#scale=2

# metrics-server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  --set 'args[0]=--kubelet-insecure-tls' -n kube-system

# 메트릭 서버 동작 확인 
k top node
NAME                  CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
myk8s-control-plane   184m         2%       953Mi           11%

# cpu 사용량 기준 정렬
kubectl top pod -A --sort-by='cpu'
NAMESPACE            NAME                                          CPU(cores)   MEMORY(bytes)
kube-system          kube-apiserver-myk8s-control-plane            53m          220Mi
kube-system          etcd-myk8s-control-plane                      27m          31Mi
kube-system          kube-controller-manager-myk8s-control-plane   22m          55Mi
kube-system          kube-scheduler-myk8s-control-plane            11m          24Mi

# 메모리 사용량 기준 정렬
kubectl top pod -A --sort-by='memory'
```

### 프로메테우스 배포 
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 배포
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 75.15.1 \
  -f kube-prometheus-stack-values.yaml --create-namespace --namespace monitoring

# prometheus 접속
open http://127.0.0.1:30001

# 그라파나 접속 admin/prom-operator
open http://127.0.0.1:30002 
```

k8s 대쉬보드 
- [12006](https://grafana.com/grafana/dashboards/12006-kubernetes-apiserver/)
- [15661](https://grafana.com/grafana/dashboards/15661-k8s-dashboard-en-20250125/)

### Kube-burner 

kube-berner 설치 
```sh
# MAC M2 기준 설치 
curl -LO https://github.com/kube-burner/kube-burner/releases/download/v1.17.3/kube-burner-V1.17.3-darwin-arm64.tar.gz
tar -xvf kube-burner-V1.17.3-darwin-arm64.tar.gz

sudo cp kube-burner /usr/local/bin

kube-burner -h

kube-burner version
Version: 1.17.3
```

**시나리오 1 테스트**
- qps 및 burst 값 

시나리오 구성 과정
1. s1-config.yaml을 통해 수행하고자 하는 시나리오를 구성한다.
2. 이때 s1-deployment.yaml을 대상으로 하여 파드 생성 테스트를 진행한다.
3. 시나리오를 종료하기 위해 s1-config-delete.yaml으로 리소스를 삭제한다.

s1-config 설정 값
- `preLoadImages: false` # kube-burnet가 실행되기 전에 이미지를 다운받는 데몬셋을 생성하지 않는다.
   - level=info msg="Pre-load: Creating DaemonSet using images [nginx:alpine] in namespace preload-kube-burner" file="pre_load.go:195"
   - level=info msg="Pre-load: Sleeping for 30s" file="pre_load.go:86"
- `waitWhenFinished: false` # 생성한 리소스에 대한 검증하지 않는다.
   - level=info msg="Waiting up to 4h0m0s for actions to be completed" file="create.go:169"
   - level=info msg="Actions in namespace kube-burner-test-0 completed" file="waiters.go:74"
- `jobIterations: 5` # s1-config를 몇 번 수행할지를 결정한다.
- `objects.replicas: 2` # deploymnet가 생성할 파드 개수 

테스트 값
- `jobIterations: 10` # jobIterations: 10, qps: 1인 경우 api-server에 파드 생성 요청을 1초당 1회 보낸다. 
- `qps: 10, burst:10` # 초당 10개의 요청 
- `jobIterations: 10, qps: 1, burst:10` `objects.replicas: 1` # qps가 1이지만 한번에 모든 JOB이 완료된다. 
- `jobIterations: 100, qps: 1, burst:100` `objects.replicas: 1` # 모든 JOB을 완료한다. 왜냐하면 burst는 최대 처리 요청에 대한 정의이기 떄문이다.
- `jobIterations: 10, qps: 1, burst:20` `objects.replicas: 2` # 20개 요청이 한번에 처리된다. 
- `jobIterations: 10, qps: 1, burst:10` `objects.replicas: 2` # 10개의 요청을 처리한 후에 초당 1개의 요청을 처리한다.
- `jobIterations: 20, qps: 2, burst:20` `objects.replicas: 2` # 20개으 순간 요청을 처리 한 후에 초당 2개의 요청을 처리한다.

정리 
> qps*burst으로 api-server에 대한 요청을 처리하는 줄 알았으나, burst가 초기에 최대 요청을 처리한 이후에 qps가 동작한다. 

```sh
# 모니터링 
watch -d kubectl get ns,pod -A

kube-burner init -h

# 부하 발생 테스트
cd senario1
kube-burner init -c s1-config.yaml --log-level debug

# kube-burner를 실행하면 ns,deployment가 생성된다.
k get deploy -A -l kube-burner-job=delete-me
NAMESPACE            NAME             READY   UP-TO-DATE   AVAILABLE   AGE
kube-burner-test-0   deployment-0-1   1/1     1            1           57s

k get pod -A -l kube-burner-job=delete-me
NAMESPACE            NAME                              READY   STATUS    RESTARTS   AGE
kube-burner-test-0   deployment-0-1-598cc6467b-mzbpd   1/1     Running   0          63s

k get ns -l kube-burner-job=delete-me
NAME                 STATUS   AGE
kube-burner-test-0   Active   66s

# kube-burner 로그 파일 생성 및 조회 확인
cat kube-burner-*.log

# config에 정의된 label(kube-burner-job: delete-me)를 기준으로 배포된 리소스 삭제한다.
kube-burner init -c s1-config-delete.yaml --log-level debug
```

**시나리오 2 테스트** 
- 노드 1대에 최대 파드(150개) 배포 시도 1

설정 값
- jobIterations: 100, qps: 300, burst: 300 objects.replicas: 1 

```sh
kube-burner init -c s1-config.yaml --log-level debug

# pending 상태의 파드 확인
k get pod -A | grep -v '1/1     Running'
NAMESPACE             NAME                                                        READY   STATUS    RESTARTS   AGE
kube-burner-test-94   deployment-94-1-76869d8568-2cr49                            0/1     Pending   0          19s
kube-burner-test-95   deployment-95-1-bbcd99594-9rg82                             0/1     Pending   0          18s
kube-burner-test-96   deployment-96-1-55976bcd96-l8skc                            0/1     Pending   0          18s
kube-burner-test-97   deployment-97-1-cb9cd857d-5bdjf                             0/1     Pending   0          18s
kube-burner-test-98   deployment-98-1-85cc9f7d4-bpnlt                             0/1     Pending   0          18s
kube-burner-test-99   deployment-99-1-89dc8948b-n4wgh                             0/1     Pending   0          18s

# 파드 이벤트 로그 조회
k describe pod -n kube-burner-test-99 | grep Events: -A5
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  59s   default-scheduler  0/1 nodes are available: 1 Too many pods. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.

# 노드 정보 조회. 파드가 생성할 수 있는 개수와 생성된 파드의 개수를 확인할수 있다. 
# 즉 노드가 가용 가능한 파드의 최대 개수를 넘어섰다.
k describe node  |grep -i capacity -A17
Capacity:
  cpu:                8
  ephemeral-storage:  61202244Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             8630612Ki
  pods:               110
Allocatable:
  cpu:                8
  ephemeral-storage:  61202244Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             8630612Ki
  pods:               110

# 파드의 최대 개수 kubelet 설정에서 확인한다. 값이 없는 경우 110개가 기본 값이다.
k get cm -n kube-system kubelet-config -o yaml

# kind 노드 접속 
docker exec -it myk8s-control-plane bash

# kubelet 설정 조회
cat /var/lib/kubelet/config.yaml

apt update && apt install vim -y

# maxPods 설정 추가 
vim /var/lib/kubelet/config.yaml
maxPods: 150

systemctl restart kubelet
systemctl status kubelet
exit

# 파드 최대 개수 변경 확인
k describe node  |grep -i capacity -A17
Capacity:
  cpu:                8
  ephemeral-storage:  61202244Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             8630612Ki
  pods:               150
Allocatable:
  cpu:                8
  ephemeral-storage:  61202244Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             8630612Ki
  pods:               150

# pending 상태의 파드가 존재하지 않는다.
k get pod -A | grep -v '1/1     Running'

kube-burner init -c s1-config-delete.yaml --log-level debug
```

시나리오 3 테스트
- 노드 1대에 최대 파드(300개) 배포 시도 2

설정 값
- jobIterations: 300, qps: 300, burst: 300 objects.replicas: 1 

```sh
kube-burner init -c s1-config.yaml --log-level debug

# maxPods 개수 400 상향
docker exec -it myk8s-control-plane bash
cat /var/lib/kubelet/config.yaml

apt update && apt install vim -y

# maxPods 값 변경 
vim /var/lib/kubelet/config.yaml
maxPods: 400

systemctl restart kubelet
systemctl status kubelet
exit

# peding 상태에 파드 조회. 약 168개가 생성되지 않는다.
kubectl get pod -A | grep -v '1/1     Running' | wc -l
     59

# 노드가 할당할 수 있는 범우의 개수를 범어나서 파드를 생성하지 못한다.
kubectl describe pod -n kube-burner-test-250 | grep Events: -A5
Warning  FailedScheduling        3m25s  default-scheduler  0/1 nodes are available: 1 Too many pods. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
  Normal   Scheduled               26s    default-scheduler  Successfully assigned kube-burner-test-250/deployment-250-1-5d76f45887-bjr7z to myk8s-control-plane
  Warning  FailedCreatePodSandBox  15s    kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "b6cd6834322ecb4afa0983d7bcd709e62513d55c24cc261c13b54844dc0f9c34": plugin type="ptp" failed (add): failed to allocate for range 0: no IP addresses available in range set: 10.244.0.1-10.244.0.254

# 파드 CIDR 범위
kubectl describe node myk8s-control-plane | grep -i podcidr
PodCIDRs:                     10.244.0.0/24

kube-burner init -c s1-config-delete.yaml --log-level debug
```

**시나리오 4 테스트**
- api-server 부하 테스트 
  - 리소스 생성 및 수정, 삭제

```sh
git clone https://github.com/kube-burner/kube-burner.git
cd examples/workloads/api-intensive

kube-burner init -c api-intensive-100.yml --log-level debug
kube-burner init -c api-intensive-500.yml --log-level debug

# kind 삭제
kind delete cluster --name myk8s 
```

https://kube-burner.github.io/kube-burner/v1.17.1/
https://github.com/kube-burner/kube-burner/tree/main/examples

## Cilium Metrics
```sh
kind create cluster --name myk8s --image kindest/node:v1.33.2 --config kind-cilium-config.yaml

# pod cidr 조회
k get nodes -o jsonpath='{.items[*].spec.podCIDR}'
10.244.0.0/22

# cilium 배포
cilium install --version 1.18.1 --set ipam.mode=kubernetes --set ipv4NativeRoutingCIDR=172.20.0.0/16 \
--set routingMode=native --set autoDirectNodeRoutes=true --set endpointRoutes.enabled=true --set directRoutingSkipUnreachable=true \
--set kubeProxyReplacement=true --set bpf.masquerade=true \
--set endpointHealthChecking.enabled=false --set healthChecking=false \
--set hubble.enabled=true --set hubble.relay.enabled=true --set hubble.ui.enabled=true \
--set hubble.ui.service.type=NodePort --set hubble.ui.service.nodePort=30003 \
--set prometheus.enabled=true --set operator.prometheus.enabled=true --set envoy.prometheus.enabled=true --set hubble.metrics.enableOpenMetrics=true \
--set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
--set debug.enabled=true 

# hubble ui
open http://127.0.0.1:30003

# metrics-server 배포 
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server --set 'args[0]=--kubelet-insecure-tls' -n kube-system

# 메트릭 서버 동작 확인
k top node
k top pod -A --sort-by='cpu'
k top pod -A --sort-by='memory'

# 프로메테우스 및 그라파나 배포
k apply -f https://raw.githubusercontent.com/cilium/cilium/1.18.1/examples/kubernetes/addons/prometheus/monitoring-example.yaml

# 프로메테우스 및 그라파나 조회
k get deploy,pod,svc,ep -n cilium-monitoring
k get cm -n cilium-monitoring
k describe cm -n cilium-monitoring prometheus
k describe cm -n cilium-monitoring grafana-config
k get svc -n cilium-monitoring

# 프로메테우스 및 그라파나 NodePort 설정
k patch svc -n cilium-monitoring prometheus -p '{"spec": {"type": "NodePort", "ports": [{"port": 9090, "targetPort": 9090, "nodePort": 30001}]}}'
k patch svc -n cilium-monitoring grafana -p '{"spec": {"type": "NodePort", "ports": [{"port": 3000, "targetPort": 3000, "nodePort": 30002}]}}'

# 접속 주소 확인
open "http://127.0.0.1:30001"  
open "http://127.0.0.1:30002"  
```

주요 지표
- lb4_backends_v3 update
- lb4_reverse_nat update
- lb4_services_v2 update
- lb_affinity_match delete
- lxc update
- runtime_config update

PromQL
```sh
# 그라파나 cilium 대쉬보드 - map ops (average node)
# 그라파나
topk(5, avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium", pod=~"$pod"}[5m])) by (pod, map_name, operation))
# 프로메테우스
topk(5, avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m])) by (pod, map_name, operation))

# cilium에서 사용되는 eBPF 맵의 총 작업(update, delete) 그리고 해당 작업에 대한 결과 success or fail 
cilium_bpf_map_ops_total
cilium_bpf_map_ops_total{k8s_app="cilium"}

# 특정 cilium 파드의 총 작업 조회
cilium_bpf_map_ops_total{k8s_app="cilium", pod="cilium-9g2kr"}

# 최근 5분 간의 데이터로 증가율 계산
rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m]) 

# 여러 시계열(metric series)의 값의 평균
avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m]))

# 집계 함수(예: sum, avg, max, rate)와 함께 사용하여 어떤 레이블(label)을 기준으로 그룹화할지를 지정하는 그룹핑(grouping) 
avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m])) by (pod) # 파드별 
avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m])) by (pod, map_name) # 파드, 맵
avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m])) by (pod, map_name, operation) # 파드, 맵, 수행 동작

# 시계열 중에서 가장 큰 k개를 선택
topk(5, avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m]))) by (pod, map_name, operation)
topk(5, avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium", pod="cilium-9g2kr"}[5m]))) by (pod, map_name, operation)
```

**iperf3**
```sh
k apply -f iperf3.yaml

# 배포 상태 확인
k get deploy,svc,pod -owide

# 서버 파드 로그 확인 : 기본 5201 포트 Listen
# 클라리언트 조회 시 로그가 기록된다.
# 테스트 1 
k logs -l app=iperf3-server -f
-----------------------------------------------------------
Server listening on 5201 (test #1)
-----------------------------------------------------------
Accepted connection from 10.244.2.147, port 57130
[  5] local 10.244.0.82 port 5201 connected to 10.244.2.147 port 57146
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-1.00   sec  15.5 GBytes   133 Gbits/sec
[  5]   1.00-2.00   sec  15.9 GBytes   137 Gbits/sec
[  5]   2.00-3.00   sec  15.7 GBytes   135 Gbits/sec
[  5]   3.00-4.00   sec  16.0 GBytes   137 Gbits/sec
[  5]   4.00-5.00   sec  15.9 GBytes   136 Gbits/sec
[  5]   5.00-5.00   sec  6.31 MBytes   133 Gbits/sec
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-5.00   sec  79.0 GBytes   136 Gbits/sec                  receiver

# tcp 5201 포트, 5초간 진행 
k exec -it deploy/iperf3-client -- iperf3 -c iperf3-server -t 5
Connecting to host iperf3-server, port 5201
[  5] local 10.244.2.147 port 57146 connected to 10.96.52.186 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  15.5 GBytes   133 Gbits/sec    2   1.62 MBytes
[  5]   1.00-2.00   sec  15.9 GBytes   137 Gbits/sec    2   1.75 MBytes
[  5]   2.00-3.00   sec  15.7 GBytes   135 Gbits/sec    2   1.75 MBytes
[  5]   3.00-4.00   sec  16.0 GBytes   137 Gbits/sec    1   1.87 MBytes
[  5]   4.00-5.00   sec  15.9 GBytes   136 Gbits/sec    0   1.87 MBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-5.00   sec  79.0 GBytes   136 Gbits/sec    7             sender
[  5]   0.00-5.00   sec  79.0 GBytes   136 Gbits/sec                  receiver
iperf Done.

# 테스트 2 
k logs -l app=iperf3-server -f
Server listening on 5201 (test #2)
-----------------------------------------------------------
Accepted connection from 10.244.2.147, port 46732
[  5] local 10.244.0.82 port 5201 connected to 10.244.2.147 port 41737
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total Datagrams
[  5]   0.00-1.00   sec  2.29 GBytes  19.7 Gbits/sec  0.005 ms  1187/76233 (1.6%)
[  5]   1.00-2.00   sec  2.28 GBytes  19.6 Gbits/sec  0.004 ms  1571/76305 (2.1%)
[  5]   2.00-3.00   sec  2.30 GBytes  19.8 Gbits/sec  0.006 ms  896/76211 (1.2%)
[  5]   3.00-4.00   sec  2.28 GBytes  19.5 Gbits/sec  0.003 ms  1786/76381 (2.3%)
[  5]   4.00-5.00   sec  2.29 GBytes  19.7 Gbits/sec  0.009 ms  1309/76257 (1.7%)
[  5]   5.00-6.00   sec  2.29 GBytes  19.7 Gbits/sec  0.003 ms  1190/76373 (1.6%)
[  5]   6.00-7.00   sec  2.29 GBytes  19.6 Gbits/sec  0.005 ms  1349/76288 (1.8%)
[  5]   7.00-8.00   sec  2.24 GBytes  19.3 Gbits/sec  0.005 ms  2756/76157 (3.6%)
[  5]   8.00-9.00   sec  2.26 GBytes  19.5 Gbits/sec  0.008 ms  2233/76409 (2.9%)
[  5]   9.00-10.00  sec  2.28 GBytes  19.6 Gbits/sec  0.003 ms  1517/76190 (2%)
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total Datagrams
[  5]   0.00-10.00  sec  22.8 GBytes  19.6 Gbits/sec  0.003 ms  15794/762804 (2.1%)  receiver

# udp 사용, 네트워크 대역폭을 20G로 설정
k exec -it deploy/iperf3-client -- iperf3 -c iperf3-server -u -b 20G
Connecting to host iperf3-server, port 5201
[  5] local 10.244.2.147 port 41737 connected to 10.96.52.186 port 5201
[ ID] Interval           Transfer     Bitrate         Total Datagrams
[  5]   0.00-1.00   sec  2.33 GBytes  20.0 Gbits/sec  76235
[  5]   1.00-2.00   sec  2.33 GBytes  20.0 Gbits/sec  76303
[  5]   2.00-3.00   sec  2.33 GBytes  20.0 Gbits/sec  76210
[  5]   3.00-4.00   sec  2.33 GBytes  20.0 Gbits/sec  76382
[  5]   4.00-5.00   sec  2.33 GBytes  20.0 Gbits/sec  76256
[  5]   5.00-6.00   sec  2.33 GBytes  20.0 Gbits/sec  76374
[  5]   6.00-7.00   sec  2.33 GBytes  20.0 Gbits/sec  76288
[  5]   7.00-8.00   sec  2.32 GBytes  20.0 Gbits/sec  76156
[  5]   8.00-9.00   sec  2.33 GBytes  20.0 Gbits/sec  76425
[  5]   9.00-10.00  sec  2.32 GBytes  20.0 Gbits/sec  76175
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total Datagrams
[  5]   0.00-10.00  sec  23.3 GBytes  20.0 Gbits/sec  0.000 ms  0/762804 (0%)  sender
[  5]   0.00-10.00  sec  22.8 GBytes  19.6 Gbits/sec  0.003 ms  15794/762804 (2.1%)  receiver
iperf Done.

# 테스트 3 
k logs -l app=iperf3-server -f
Server listening on 5201 (test #3)
-----------------------------------------------------------
Accepted connection from 10.244.2.147, port 51716
[  5] local 10.244.0.82 port 5201 connected to 10.244.2.147 port 51732
[  8] local 10.244.0.82 port 5201 connected to 10.244.2.147 port 51744
[ ID][Role] Interval           Transfer     Bitrate         Retr  Cwnd
[  5][RX-S]   0.00-1.00   sec  1.46 GBytes  12.5 Gbits/sec
[  8][TX-S]   0.00-1.00   sec  14.1 GBytes   121 Gbits/sec    1   3.50 MBytes
[  5][RX-S]   1.00-2.00   sec  12.6 GBytes   108 Gbits/sec
[  8][TX-S]   1.00-2.00   sec  2.87 GBytes  24.7 Gbits/sec    1   3.50 MBytes
[  5][RX-S]   2.00-3.00   sec  14.0 GBytes   120 Gbits/sec
[  8][TX-S]   2.00-3.00   sec  1.40 GBytes  12.0 Gbits/sec    0   3.50 MBytes
[  5][RX-S]   3.00-4.00   sec  14.1 GBytes   121 Gbits/sec
[  8][TX-S]   3.00-4.00   sec  1.41 GBytes  12.1 Gbits/sec    0   3.50 MBytes
[  5][RX-S]   4.00-5.00   sec  14.2 GBytes   122 Gbits/sec
[  8][TX-S]   4.00-5.00   sec  1.42 GBytes  12.2 Gbits/sec    0   3.50 MBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID][Role] Interval           Transfer     Bitrate         Retr
[  5][RX-S]   0.00-5.00   sec  56.3 GBytes  96.8 Gbits/sec                  receiver
[  8][TX-S]   0.00-5.00   sec  21.2 GBytes  36.4 Gbits/sec    2             sender

# 5초간 양방향 통신 설정, 기존에는 단방향
k exec -it deploy/iperf3-client -- iperf3 -c iperf3-server -t 5 --bidir
Connecting to host iperf3-server, port 5201
[  5] local 10.244.2.147 port 51732 connected to 10.96.52.186 port 5201
[  7] local 10.244.2.147 port 51744 connected to 10.96.52.186 port 5201
[ ID][Role] Interval           Transfer     Bitrate         Retr  Cwnd
[  5][TX-C]   0.00-1.00   sec  1.47 GBytes  12.6 Gbits/sec    0   3.62 MBytes
[  7][RX-C]   0.00-1.00   sec  14.1 GBytes   121 Gbits/sec
[  5][TX-C]   1.00-2.00   sec  12.5 GBytes   108 Gbits/sec    1   3.62 MBytes
[  7][RX-C]   1.00-2.00   sec  2.86 GBytes  24.6 Gbits/sec
[  5][TX-C]   2.00-3.00   sec  14.0 GBytes   120 Gbits/sec    0   3.62 MBytes
[  7][RX-C]   2.00-3.00   sec  1.40 GBytes  12.0 Gbits/sec
[  5][TX-C]   3.00-4.00   sec  14.1 GBytes   121 Gbits/sec    0   3.62 MBytes
[  7][RX-C]   3.00-4.00   sec  1.41 GBytes  12.1 Gbits/sec
[  5][TX-C]   4.00-5.00   sec  14.2 GBytes   122 Gbits/sec    2   4.18 MBytes
[  7][RX-C]   4.00-5.00   sec  1.42 GBytes  12.2 Gbits/sec
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID][Role] Interval           Transfer     Bitrate         Retr
[  5][TX-C]   0.00-5.00   sec  56.3 GBytes  96.8 Gbits/sec    3             sender
[  5][TX-C]   0.00-5.00   sec  56.3 GBytes  96.8 Gbits/sec                  receiver
[  7][RX-C]   0.00-5.00   sec  21.2 GBytes  36.4 Gbits/sec    2             sender
[  7][RX-C]   0.00-5.00   sec  21.2 GBytes  36.4 Gbits/sec                  receiver
iperf Done.

# 테스트 4
# 10초간 2 개의 커넥션을 연결을 설정 
k exec -it deploy/iperf3-client -- iperf3 -c iperf3-server -t 10 -P 2
Connecting to host iperf3-server, port 5201
[  5] local 10.244.2.147 port 38910 connected to 10.96.52.186 port 5201
[  7] local 10.244.2.147 port 38914 connected to 10.96.52.186 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  8.02 GBytes  68.9 Gbits/sec   11   1.25 MBytes
[  7]   0.00-1.00   sec  8.01 GBytes  68.8 Gbits/sec   19    639 KBytes
[SUM]   0.00-1.00   sec  16.0 GBytes   138 Gbits/sec   30
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   1.00-2.00   sec  7.92 GBytes  68.1 Gbits/sec   14   1.31 MBytes
[  7]   1.00-2.00   sec  7.92 GBytes  68.0 Gbits/sec   15   1.75 MBytes
[SUM]   1.00-2.00   sec  15.8 GBytes   136 Gbits/sec   29
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   2.00-3.00   sec  8.29 GBytes  71.2 Gbits/sec   12   1.31 MBytes
[  7]   2.00-3.00   sec  8.29 GBytes  71.2 Gbits/sec   11   1.19 MBytes
[SUM]   2.00-3.00   sec  16.6 GBytes   142 Gbits/sec   23
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   3.00-4.00   sec  8.12 GBytes  69.7 Gbits/sec   14   1.31 MBytes
[  7]   3.00-4.00   sec  8.11 GBytes  69.7 Gbits/sec    8   1.19 MBytes
[SUM]   3.00-4.00   sec  16.2 GBytes   139 Gbits/sec   22
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   4.00-5.00   sec  8.29 GBytes  71.2 Gbits/sec   14   1.31 MBytes
[  7]   4.00-5.00   sec  8.29 GBytes  71.2 Gbits/sec    3   1.19 MBytes
[SUM]   4.00-5.00   sec  16.6 GBytes   142 Gbits/sec   17
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   5.00-6.00   sec  8.12 GBytes  69.7 Gbits/sec    5   1.31 MBytes
[  7]   5.00-6.00   sec  8.12 GBytes  69.7 Gbits/sec    6   1.19 MBytes
[SUM]   5.00-6.00   sec  16.2 GBytes   139 Gbits/sec   11
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   6.00-7.00   sec  7.89 GBytes  67.7 Gbits/sec   26   1.31 MBytes
[  7]   6.00-7.00   sec  7.89 GBytes  67.7 Gbits/sec   42   1023 KBytes
[SUM]   6.00-7.00   sec  15.8 GBytes   135 Gbits/sec   68
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   7.00-8.00   sec  7.62 GBytes  65.5 Gbits/sec    1   1.31 MBytes
[  7]   7.00-8.00   sec  7.62 GBytes  65.5 Gbits/sec   10   1.12 MBytes
[SUM]   7.00-8.00   sec  15.2 GBytes   131 Gbits/sec   11
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   8.00-9.00   sec  7.65 GBytes  65.7 Gbits/sec    2   1.31 MBytes
[  7]   8.00-9.00   sec  7.65 GBytes  65.7 Gbits/sec   13    959 KBytes
[SUM]   8.00-9.00   sec  15.3 GBytes   131 Gbits/sec   15
- - - - - - - - - - - - - - - - - - - - - - - - -
[  5]   9.00-10.00  sec  5.89 GBytes  50.6 Gbits/sec    0   1.31 MBytes
[  7]   9.00-10.00  sec  5.89 GBytes  50.6 Gbits/sec    0   1.12 MBytes
[SUM]   9.00-10.00  sec  11.8 GBytes   101 Gbits/sec    0
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  77.8 GBytes  66.8 Gbits/sec   99             sender
[  5]   0.00-10.00  sec  77.8 GBytes  66.8 Gbits/sec                  receiver
[  7]   0.00-10.00  sec  77.8 GBytes  66.8 Gbits/sec  127             sender
[  7]   0.00-10.00  sec  77.8 GBytes  66.8 Gbits/sec                  receiver
[SUM]   0.00-10.00  sec   156 GBytes   134 Gbits/sec  226             sender
[SUM]   0.00-10.00  sec   156 GBytes   134 Gbits/sec                  receiver
iperf Done.

# iperf3 리소스 삭제 
kubectl delete deploy iperf3-server iperf3-client && kubectl delete svc iperf3-server 

# kind 삭제
kind delete cluster --name myk8s 
```