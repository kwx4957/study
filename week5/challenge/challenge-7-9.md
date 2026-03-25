- `도전과제7` 만약 **west** 는 **요청 클라이언트만** 있고, east 는 **대상 서버만** 존재 시, ClusterMesh 서비스 통신 **최적 설정**을 샘플 App대상으로 해보기
    - 대상 서버가 없는 west 에 Service(Global) 를 만들어야 되는지?
    - west 요청 클라이언트가 호출하는 주소(엔드포인트)는 어떤 주소가 되는지?
- `도전과제8` Cilium ClusterMesh 환경에서 **NetworkPolicies** : 실습 해보자 - [Docs](https://docs.cilium.io/en/stable/network/clustermesh/policy/)
- `도전과제9` Cilium DataStore(**Kvstore**) 를 설정해보고, Cilium 기본 CRD 모드와의 장단점 비교 정리 - [Docs](https://docs.cilium.io/en/stable/overview/component-overview/)
    
    ```bash
    #
    cat << EOF > etcd.yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: etcd
      namespace: kube-system
      labels:
        app: etcd
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:v3.5.0
        command:
          - /usr/local/bin/etcd
        args:
          - --name=etcd0
          - --data-dir=/etcd-data
          - --listen-client-urls=http://0.0.0.0:2379
          - --advertise-client-urls=http://etcd.kube-system.svc.cluster.local:2379
        ports:
          - containerPort: 2379
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: etcd
      namespace: kube-system
    spec:
      ports:
      - port: 2379
        targetPort: 2379
      selector:
        app: etcd      
    EOF
    
    **kubectl apply -f etcd.yaml**
    
    #
    helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
    **--set etcd.enabled=true --set identityAllocationMode=kvstore --set "etcd.endpoints[0]=http://etcd.kube-system.svc.cluster.local:2379"**
    
    etcd:
      enabled: true
      endpoints:
      - http://etcd.kube-system.svc.cluster.local:2379
    
    **kubectl rollout restart deploy cilium-operator -n kube-system
    kubectl rollout restart ds cilium -n kube-system**
    
    **#
    kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium status
    *KVStore**:                 Ok   **etcd**: 1/1 connected, leases=1, lock leases=1, has-quorum=true: http://etcd.kube-system.svc.cluster.local:2379 - 3.5.0 (Leader)*
    **...**
    
    ```