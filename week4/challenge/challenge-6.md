## 6. Target 에 대한 문제 해결
helm 차트로 배포한 프로메테우스가 어떤 자원을 생성하는지 확인하고, kube-controll-manager, kube-proxy, sceduler, etcd등 수집하지 못하는 리소스에 대해서 메트릭을 수집하자 

```sh
k delete -f https://raw.githubusercontent.com/cilium/cilium/1.18.0/examples/kubernetes/addons/prometheus/monitoring-example.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# default value 편집 
cat <<EOT > monitor-values.yaml
prometheus:
  prometheusSpec:
    scrapeInterval: "15s"
    evaluationInterval: "15s"
  service:
    type: NodePort
    nodePort: 30001

grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator
  service:
    type: NodePort
    nodePort: 30002

alertmanager:
  enabled: false
defaultRules:
  create: false
prometheus-windows-exporter:
  prometheus:
    monitor:
      enabled: false
EOT
```

prometheus 배포 
```sh
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 75.15.1 \
-f monitor-values.yaml --create-namespace --namespace monitoring

helm list -n monitoring
kube-prometheus-stack	monitoring	1       	2025-08-10 02:17:46.638383982 +0900 KST	deployed	kube-prometheus-stack-75.15.1	v0.83.0

promtheus 리소스 전부 조회
```sh
k get all -n monitoring
```

k8s 컴포넌트에 대해서 기본적으로 수집되는 서비스모니터 확인
```sh
k get prometheus,servicemonitors -n monitoring
NAME                                                                VERSION   DESIRED   READY   RECONCILED   AVAILABLE   AGE
prometheus.monitoring.coreos.com/kube-prometheus-stack-prometheus   v3.5.0    1         1       True         True        19m

NAME                                                                                  AGE
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-apiserver                  19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-coredns                    19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-grafana                    19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kube-controller-manager    19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kube-etcd                  19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kube-proxy                 19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kube-scheduler             19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kube-state-metrics         19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-kubelet                    19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-operator                   19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-prometheus                 19m
servicemonitor.monitoring.coreos.com/kube-prometheus-stack-prometheus-node-exporter   19m

# crd 조회
k get crd | grep monitoring
alertmanagerconfigs.monitoring.coreos.com    2025-08-09T17:17:44Z
alertmanagers.monitoring.coreos.com          2025-08-09T17:17:44Z
podmonitors.monitoring.coreos.com            2025-08-09T17:17:44Z
probes.monitoring.coreos.com                 2025-08-09T17:17:44Z
prometheusagents.monitoring.coreos.com       2025-08-09T17:17:44Z
prometheuses.monitoring.coreos.com           2025-08-09T17:17:45Z
prometheusrules.monitoring.coreos.com        2025-08-09T17:17:45Z
scrapeconfigs.monitoring.coreos.com          2025-08-09T17:17:45Z
servicemonitors.monitoring.coreos.com        2025-08-09T17:17:45Z
thanosrulers.monitoring.coreos.com           2025-08-09T17:17:45Z

k exec -it sts/prometheus-kube-prometheus-stack-prometheus -n monitoring -c prometheus -- prometheus --version
prometheus, version 3.5.0 (branch: HEAD, revision: 8be3a9560fbdd18a94dedec4b747c35178177202)
  build user:       root@4451b64cb451
  build date:       20250714-16:18:17
  go version:       go1.24.5
  platform:         linux/arm64
  tags:             netgo,builtinassets
```

메트릭을 수집하지 못하는 컴포넌트
- kube-controller-manager 
- kube-scheduler
- etcd
- kube-proxy

```sh
# kube-prometheus-stack-kube-controller-manager 서비스 모니터 설정 확인 
k describe servicemonitors.monitoring.coreos.com -n monitoring kube-prometheus-stack-kube-controller-manager
Name:         kube-prometheus-stack-kube-controller-manager
Namespace:    monitoring
Labels:       app=kube-prometheus-stack-kube-controller-manager
              app.kubernetes.io/instance=kube-prometheus-stack
              app.kubernetes.io/managed-by=Helm
              app.kubernetes.io/part-of=kube-prometheus-stack
              app.kubernetes.io/version=75.15.1
              chart=kube-prometheus-stack-75.15.1
              heritage=Helm
              release=kube-prometheus-stack
Annotations:  meta.helm.sh/release-name: kube-prometheus-stack
              meta.helm.sh/release-namespace: monitoring
API Version:  monitoring.coreos.com/v1
Kind:         ServiceMonitor
Metadata:
  Creation Timestamp:  2025-08-09T17:17:59Z
  Generation:          1
  Resource Version:    84910
  UID:                 7e889e37-1cb3-45fd-993a-e22c7ad6aa01
Spec:
  Endpoints:
    Bearer Token File:  /var/run/secrets/kubernetes.io/serviceaccount/token
    Port:               http-metrics
    Scheme:             https
    Tls Config:
      Ca File:               /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      Insecure Skip Verify:  true
  Job Label:                 jobLabel
  Namespace Selector:
    Match Names:
      kube-system
  Selector:
    Match Labels:
      App:      kube-prometheus-stack-kube-controller-manager
      Release:  kube-prometheus-stack

k get servicemonitors.monitoring.coreos.com -n monitoring kube-prometheus-stack-kube-controller-manager -o yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  creationTimestamp: "2025-08-09T17:17:59Z"
  generation: 1
  labels:
    app: kube-prometheus-stack-kube-controller-manager
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 75.15.1
    chart: kube-prometheus-stack-75.15.1
    heritage: Helm
    release: kube-prometheus-stack
  name: kube-prometheus-stack-kube-controller-manager
  namespace: monitoring
  resourceVersion: "84910"
  uid: 7e889e37-1cb3-45fd-993a-e22c7ad6aa01
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    port: http-metrics
    scheme: https
    tlsConfig:
      caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecureSkipVerify: true
  jobLabel: jobLabel
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      app: kube-prometheus-stack-kube-controller-manager
      release: kube-prometheus-stack

# kube-prometheus-stack-kube-controller-manager 설정을 확인한 결과
# 프로메테우스가 메트릭을 수집하기 위해서 포트가 열려있어야 하는데 로컬로 구성이 되어있어서 메트릭을 수집하지 못한다.
k -n kube-system get pods -l component=kube-controller-manager -o yaml | grep -E -- '--secure-port|--bind-address|--authentication'
      - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
      - --bind-address=127.0.0.1

# 포트 조회
ss -ntlp |grep 10257
LISTEN 0      4096        127.0.0.1:10257      0.0.0.0:*    users:(("kube-controller",pid=1226,fd=3))

# 설정 변경
# 스케줄러도 동일하며, kubelet이 직접 관리하는 파드라 자동으로 재시작한다. etcd의 경우에는 약긴의 다운타임이 발생한다. 
vi /etc/kubernetes/manifests/kube-controller-manager.yaml
      - --bind-address=0.0.0.0
vi /etc/kubernetes/manifests/kube-scheduler.yaml
      - --bind-address=0.0.0.0
vi /etc/kubernetes/manifests/etcd.yaml
    - --listen-metrics-urls=http://192.168.10.100:2381

ss -ntlp | grep 10257
LISTEN 0      4096                *:10257            *:*    users:(("kube-controller",pid=30667,fd=3))

# kube-prxoy의 경우에는 다르다
# 0.0.0.0으로 되어있으나 metrics는 다른 설정을 변경해야 한다.
k describe cm -n kube-system kube-proxy  |grep bind
bindAddress: 0.0.0.0

# 하단의 설정으로 변경한다.
k edit -n kube-system cm kube-proxy
metricsBindAddress: "0.0.0.0"

k rollout restart -n kube-system daemonset kube-proxy

ss -tnlp |grep proxy
LISTEN 0      4096                *:10249            *:*    users:(("kube-proxy",pid=36912,fd=11))
LISTEN 0      4096                *:10256            *:*    users:(("kube-proxy",pid=36912,fd=10))
```