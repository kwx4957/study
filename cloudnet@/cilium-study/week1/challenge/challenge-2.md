- `도전과제` kubeadm Configuration 를 사용해서 node-ip 를 지정해서 init/join 해보자 - [Docs](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/)
    
    ```bash
    # 예시
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-ip: "192.168.10.101"
    ```