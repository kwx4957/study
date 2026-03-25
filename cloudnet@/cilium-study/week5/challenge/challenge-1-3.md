- `도전과제1` **Descheduler** for Kubernetes : Pod의 상태를 확인하여 조건에 성립하는 Pod를 Eviction하여 원하는 상태로 만듬 - [Github](https://github.com/kubernetes-sigs/descheduler) , [Blog](https://ybchoi.com/19)
    
    ```bash
    # Run As A **Deployment**
    kubectl kustomize 'https://github.com/kubernetes-sigs/descheduler.git/kubernetes/**deployment**?ref=release-1.33' | kubectl apply -f -
    *serviceaccount/descheduler-sa created
    clusterrole.rbac.authorization.k8s.io/descheduler-cluster-role created
    clusterrolebinding.rbac.authorization.k8s.io/descheduler-cluster-role-binding created
    configmap/descheduler-policy-configmap created
    deployment.apps/descheduler created*
    
    ~~# Run As A **CronJob**
    kubectl kustomize 'https://github.com/kubernetes-sigs/descheduler.git/kubernetes/**cronjob**?ref=release-1.33' | kubectl apply -f -
    
    # Run As A **Job**
    kubectl kustomize 'https://github.com/kubernetes-sigs/descheduler.git/kubernetes/**job**?ref=release-1.33' | kubectl apply -f -~~
    
    #
    kubectl get deploy -n kube-system descheduler
    kubectl get cm -n kube-system descheduler-policy-configmap
    
    kubectl describe pod -n kube-system -l app=descheduler
    **kubectl describe cm -n kube-system descheduler-policy-configmap**
    ...
    **policy.yaml**:
    ----
    apiVersion: "**descheduler/v1alpha2**"
    kind: "**DeschedulerPolicy**"
    profiles:
      - name: ProfileName
        **pluginConfig**:
        - name: "**DefaultEvictor**"
        - name: "**RemovePodsViolatingInterPodAntiAffinity**"
        - name: "**RemoveDuplicates**"
        - name: "**LowNodeUtilization**"
          **args**:
            **thresholds**:
              "cpu" : 20
              "memory": 20
              "pods": 20
            **targetThresholds**:
              "cpu" : 50
              "memory": 50
              "pods": 50
              
        **plugins**:
          **balance**:
            enabled:
              - "**LowNodeUtilization**"
              - "**RemoveDuplicates**"
          **deschedule**:
            enabled:
              - "**RemovePodsViolatingInterPodAntiAffinity**"
    
    ```
    
    ![image.png](attachment:932b143e-7fa2-43f3-b426-7f3c200f197b:image.png)
    
    ```bash
    #
    
    #
    ```
    
- `도전과제2` Cilium BGP로 **ClusterIP**를 광고해보고 통신 확인 해보시기 바랍니다 - [Docs](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/#clusterip)
- `도전과제3` **Internal Traffic Policy : Local** 설정 시 CusterIP로 호출 시 어떻게 동작하는지 정리해보시기 바랍니다 - [Docs](https://kubernetes.io/docs/concepts/services-networking/service-traffic-policy/)