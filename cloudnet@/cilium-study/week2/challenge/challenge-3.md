## 3. Prometheus을 통한 cilium 메트릭 수집
```sh
# 전체 helm
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
--set prometheus.metricsService=true \
--set prometheus.serviceMonitor.enabled=true \
--set prometheus.serviceMonitor.labels.release="prometheus"
--set hubble.metrics.serviceMonitor.enabled=true \
--set hubble.metrics.serviceMonitor.labels.release="prometheus" \
--set envoy.prometheus.enabled=true \
--set envoy.prometheus.serviceMonitor.enabled=true \
--set envoy.prometheus.serviceMonitor.labels.release="prometheus" \
--set operator.prometheus.metricsService=true \
--set operator.prometheus.serviceMonitor.enabled=true \
--set operator.prometheus.serviceMonitor.labels.release="prometheus" \
--set hubble.relay.prometheus.enabled=true \
--set hubble.relay.prometheus.serviceMonitor.enabled=true \
--set hubble.relay.prometheus.serviceMonitor.labels.release="prometheus" 
```

## 프로메테우스 배포

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n prometheus --create-namespace

# 그라나나 대쉬보드 접속
# admin / prom-operator
kubectl --namespace prometheus get secrets prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

대쉬보드 항목에서 하단의 항목들을 추가한다. 하지만 해당 설정은 그라파나에서 cilium에 대한 메트릭을 시각화하기 위한 과정에 불과하다. cilium에서도 추가적인 설정을 구성해야 한다.

- cilium(21431)
- cilium-envoy(21329)
- [hubble-network-overview-ns(19424)](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/hubble/dashboards/hubble-network-overview-namespace.json)
- [hubble-l7-workload(19423)](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/hubble/dashboards/hubble-l7-http-metrics-by-workload.json)
- [hubble dns-namspace(19425)](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/hubble/dashboards/hubble-dns-namespace.json)
- [hubble mertircs(16613)](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/cilium-operator/dashboards/cilium-operator-dashboard.json)
- [cilium-operator(16612)](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/files/cilium-operator/dashboards/cilium-operator-dashboard.json)

```sh
# Cilium-agent 메트릭 수집을 위한 서비스 및 서비스 모니터 생성
# 만일 kube-prometheus-stack으로 배포한 경우 서비스 모니터에 라벨을 추기해야 한다. 그렇지 않을 경우 프로메테우스가 서비스 모니터를 인지하지 못한다.
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
--set prometheus.metricsService=true \
--set prometheus.serviceMonitor.enabled=true \
--set prometheus.serviceMonitor.labels.release="prometheus"

k get svc -A -l k8s-app=cilium
NAMESPACE     NAME           TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
kube-system   cilium-agent   ClusterIP   None          <none>        9962/TCP   101s

k get servicemonitors.monitoring.coreos.com -n kube-system
NAME           AGE
cilium-agent   2m4s

# 수집되는 파드 정보 확인
k -n kube-system get ds/cilium -o json | jq |grep -i prometheus -B3
"annotations": {
    "prometheus.io/port": "9962",
    "prometheus.io/scrape": "true"

# 수집대상 서비스 
# headless 서비스로 생성되어 프로메테우스가 서비스 디스커버리를 통해 cilium 메트릭을 수집되는 것을 확인할 수 있다.
k -n kube-system describe svc cilium-agent
Name:                     cilium-agent
Namespace:                kube-system
Labels:                   app.kubernetes.io/managed-by=Helm
                          app.kubernetes.io/name=cilium-agent
                          app.kubernetes.io/part-of=cilium
                          k8s-app=cilium
Annotations:              meta.helm.sh/release-name: cilium
                          meta.helm.sh/release-namespace: kube-system
Selector:                 k8s-app=cilium
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       None
IPs:                      None
Port:                     metrics  9962/TCP
TargetPort:               prometheus/TCP
Endpoints:                192.168.10.101:9962,192.168.10.100:9962,192.168.10.102:9962
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>

# cilium 서비스모니터
k -n kube-system describe servicemonitors.monitoring.coreos.com cilium-agent
Name:         cilium-agent
Namespace:    kube-system
Labels:       app.kubernetes.io/managed-by=Helm
              app.kubernetes.io/part-of=cilium
              release=prometheus
Annotations:  meta.helm.sh/release-name: cilium
              meta.helm.sh/release-namespace: kube-system
API Version:  monitoring.coreos.com/v1
Kind:         ServiceMonitor
Spec:
  Endpoints:
    Honor Labels:  true
    Interval:      10s
    Path:          /metrics
    Port:          metrics
    Relabelings:
      Action:       replace
      Replacement:  ${1}
      Source Labels:
        __meta_kubernetes_pod_node_name
      Target Label:  node
  Namespace Selector:
    Match Names:
      kube-system
  Selector:
    Match Labels:
      app.kubernetes.io/name:  cilium-agent
  Target Labels:
    k8s-app
Events:  <none>
```

하지만 일련의 과정은 cilium에 대한 메트릭만을 가져온다. cilium 외에도 envoy, hubble, hubble-relay, cilium-operator 메트릭도 가져오자.
```sh
ss -ntlp |grep cilium
LISTEN 0      4096          0.0.0.0:9964       0.0.0.0:*    users:(("cilium-envoy",pid=5503,fd=24))
LISTEN 0      4096                *:9963             *:*    users:(("cilium-operator",pid=5530,fd=7))
LISTEN 0      4096                *:9962             *:*    users:(("cilium-agent",pid=12666,fd=7))
LISTEN 0      4096                *:9965             *:*    users:(("cilium-agent",pid=12666,fd=45))

# hubble, hubble-relay, envoy, cilum-operator에 대한 메트릭을 수집한다.
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
--set hubble.metrics.serviceMonitor.enabled=true \
--set hubble.metrics.serviceMonitor.labels.release="prometheus" \
--set envoy.prometheus.enabled=true \
--set envoy.prometheus.serviceMonitor.enabled=true \
--set envoy.prometheus.serviceMonitor.labels.release="prometheus" \
--set operator.prometheus.metricsService=true \
--set operator.prometheus.serviceMonitor.enabled=true \
--set operator.prometheus.serviceMonitor.labels.release="prometheus" \
--set hubble.relay.prometheus.enabled=true \
--set hubble.relay.prometheus.serviceMonitor.enabled=true \
--set hubble.relay.prometheus.serviceMonitor.labels.release="prometheus" 

k get servicemonitors.monitoring.coreos.com -n kube-system
NAME              AGE
cilium-agent      109m
cilium-envoy      16m
cilium-operator   2m13s
hubble            2m13s
hubble-relay      16m
```

정리하자면 cilium에서 총 5 종류의 메트릭을 가져올 수가 있다. 각각의 애플리케이션에 이 수집하는 포트 정보이다.
- cilium(9962)
- cilium-operator(9963)
- cilium-envoy(9964)
- hubble(9965)
- hubble-relay(9966)

cilium와 관련된 모든 메트릭을 가져오지만, 모든 메트릭이 도움이 될까라는 의문이 든다. 나중에 시간이 되면 중복된 메트릭을 제거하는 작업을 진행해야 해봐야겠다.

https://docs.cilium.io/en/stable/observability/grafana/   
https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/values.yaml#L2314   
https://prometheus-operator.dev/docs/platform/troubleshooting/#troubleshooting-servicemonitor-changes. 