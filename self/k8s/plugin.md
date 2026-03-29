## k8s 도구 또는 플러그인 정리

### 플러그인
- [krew](https://krew.sigs.k8s.io/docs/user-guide/quickstart/) : 플러그인 관리 도구 
- [kubecolor](https://kubecolor.github.io/setup/install/) : kubectl 출력 색상화
- [neat](https://github.com/itaysk/kubectl-neat) : k8s 리소스에 대해 원본 yaml 출력 
- [lineage](https://github.com/tohjustin/kube-lineage) : k8s 리소스 관계도 출력
- [kubectx, kubens](https://github.com/ahmetb/kubectx) : 클러스터 전환
- [tree](https://github.com/ahmetb/kubectl-tree) : 특정 리소스와 연결된 하위 리소스를 트리 구조로 보여준다
- [sniff](https://github.com/eldadru/ksniff) : 파드의 네트워크 트래픽을 가로채서 로컬의 Wireshark로 전달합니다
- [kpexec](https://github.com/ssup2/kpexec) : 파드 내에 가장 높은 권한으로 접근한다. 권한이 없거나 별도의 디버깅 도구가 없는 경우 활용

### 보안 
- [kube-bench](https://github.com/aquasecurity/kube-bench)
- [kube-hunter](https://github.com/aquasecurity/kube-hunter)
- [k8s-goat](https://github.com/madhuakula/kubernetes-goat)
- [trivy](https://github.com/aquasecurity/trivy)

### 모니터링 
- [k9s](https://k9scli.io/)
- [openlens](https://github.com/MuhammedKalkan/OpenLens)

### etc
- [sonobuoy](https://github.com/vmware-tanzu/sonobuoy): k8s 적합성 테스트


https://krew.sigs.k8s.io/plugins/