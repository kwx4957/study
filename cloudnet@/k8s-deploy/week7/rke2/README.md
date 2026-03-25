### RKE2

> Cloudnet@ k8s Deploy 7주차 스터디를 진행하며 정리한 글입니다.

```sh
vagrant up 
vagrant status
vagrant destroy -f && rm -rf .vagrant

vagrant ssh k8s-node1

# RKE2 설치
curl -sfL https://get.rke2.io --output install.sh
chmod +x install.sh

# RKE2 서버 설치
INSTALL_RKE2_CHANNEL=v1.33 ./install.sh
Installed:
  rke2-common-1.33.7~rke2r3-0.el9.aarch64           rke2-selinux-0.22-1.el9.noarch          
  rke2-server-1.33.7~rke2r3-0.el9.aarch64  

# 버전 확인
rke2 --version
rke2 version v1.33.7+rke2r3 (7e4fd1a82edf497cab91c220144619bbad659cf4)
go version go1.24.11 X:boringcrypto

# 레포지토리 확인
dnf repolist
rancher-rke2-1.33-stable                      Rancher RKE2 1.33 (v1.33)
rancher-rke2-common-stable                    Rancher RKE2 Common (v1.33)

tree /etc/yum.repos.d/
/etc/yum.repos.d/
├── rancher-rke2.repo
├── rocky-addons.repo
├── rocky-devel.repo
├── rocky-extras.repo
└── rocky.repo

# 새 레포지토리 생성
cat /etc/yum.repos.d/rancher-rke2.repo
[rancher-rke2-common-stable]
name=Rancher RKE2 Common (v1.33)
baseurl=https://rpm.rancher.io/rke2/stable/common/centos/9/noarch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://rpm.rancher.io/public.key
[rancher-rke2-1.33-stable]
name=Rancher RKE2 1.33 (v1.33)
baseurl=https://rpm.rancher.io/rke2/stable/1.33/centos/9/aarch64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://rpm.rancher.io/public.key


tree /etc/rancher/
/etc/rancher/
└── rke2

tree /var/lib/rancher/
/var/lib/rancher/
└── rke2
    ├── agent
    │   ├── containerd
    │   │   └── io.containerd.snapshotter.v1.overlayfs
    │   │       └── snapshots
    │   └── logs
    ├── data
    └── server
8 directories, 0 files

rke2 --h
COMMANDS:
   server           Run management server
   agent            Run node agent
   etcd-snapshot    Manage etcd snapshots
   certificate      Manage RKE2 certificates
   secrets-encrypt  Control secrets encryption and keys rotation
   token            Manage tokens
   completion       Install shell completion script

# RKE2 설정, cni 및 ip 설정, 불필요한 컴포넌트 비활성화
cat << EOF > /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"

debug: true

cni: canal

bind-address: 192.168.10.11
advertise-address: 192.168.10.11
node-ip: 192.168.10.11

disable-cloud-controller: true

disable:
  - servicelb
  - rke2-coredns-autoscaler
  - rke2-ingress-nginx
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook
EOF

cat /etc/rancher/rke2/config.yaml

mkdir -p /var/lib/rancher/rke2/server/manifests/

# 네트워크 인터페이스 및 autoscaler 설정을 위한 HelmChartConfig 생성
cat << EOF > /var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-canal
  namespace: kube-system
spec:
  valuesContent: |-
    flannel:
      iface: "enp0s9"
EOF

cat << EOF > /var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    autoscaler:
      enabled: false
EOF

# RKE2 서버 실행
systemctl enable --now rke2-server.service
systemctl status rke2-server --no-pager
● rke2-server.service - Rancher Kubernetes Engine v2 (server)
     Loaded: loaded (/usr/lib/systemd/system/rke2-server.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-02-17 21:03:14 KST; 37s ago

# 시스템 로그
Feb 17 21:03:32 k8s-node1 rke2[6474]: time="2026-02-17T21:03:32+09:00" level=debug msg="Waiting for Ready condition to be updated for Kubelet Port assignment"

# rke 부모프세스 및 kubeelt, containerd 자식 프로세스 확인
pstree -a | grep -v color | grep 'rke2$' -A5
  |-rke2
  |   |-containerd -c /var/lib/rancher/rke2/agent/etc/containerd/config.toml
  |   |   `-10*[{containerd}]
  |   |-kubelet --volume-plugin-dir=/var/lib/kubelet/volumeplugins --file-check-frequency=5s --sync-frequency=30s...
  |   |   `-16*[{kubelet}]
  |   `-11*[{rke2}]


pstree -a | grep -v color | grep 'containerd-shim ' -A2
  |-containerd-shim -namespace k8s.io -id93ea8a186793de11157485771c3
  |   |-kube-proxy --cluster-cidr=10.42.0.0/16 --conntrack-max-per-core=0 --conntrack-tcp-timeout-close-wait=0s...
  |   |   `-7*[{kube-proxy}]
--
  |-containerd-shim -namespace k8s.io -id6e582b0bf6fd4b98d230e7ded1b
  |   |-etcd --config-file=/var/lib/rancher/rke2/server/db/etcd/config
  |   |   `-9*[{etcd}]
--
  |-containerd-shim -namespace k8s.io -ida0eb4e94c04c0e553242458d7ba
  |   |-kube-apiserver --admission-control-config-file=/etc/rancher/rke2/rke2-pss.yaml --advertise-address=192.168.10.11...
  |   |   `-10*[{kube-apiserver}]
--
  |-containerd-shim -namespace k8s.io -id0a489b382d23227a17e72a5f138
  |   |-kube-controller --permit-port-sharing=true --flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins--terminated-pod-gc-thres
  |   |   `-6*[{kube-controller}]
--
  |-containerd-shim -namespace k8s.io -idac27d2da9b9825f4f8e556716c4
  |   |-kube-scheduler --permit-port-sharing=true ...
  |   |   `-9*[{kube-scheduler}]
--
  |-containerd-shim -namespace k8s.io -id75170d54af34f10c3aa0555b212
  |   |-flanneld --ip-masq --kube-subnet-mgr --iptables-forward-rules=false --ip-blackhole-route
  |   |   |-(timeout)
--
  |-containerd-shim -namespace k8s.io -idb55cbea4845e681395bb70eac24
  |   |-metrics-server --secure-port=10250 --cert-dir=/tmp --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname...
  |   |   `-8*[{metrics-server}]
--
  |-containerd-shim -namespace k8s.io -id332307aeb30e838d7e2c167c6b0
  |   |-coredns -conf /etc/coredns/Corefile
  |   |   `-6*[{coredns}]


# kubeconfig 복사
mkdir ~/.kube

ls -l /etc/rancher/rke2/rke2.yaml
-rw-r--r--. 1 root root 2973 Feb 17 21:02 /etc/rancher/rke2/rke2.yaml

cp /etc/rancher/rke2/rke2.yaml ~/.kube/config

tree /etc/rancher/
/etc/rancher/
├── node
│   └── password
└── rke2
    ├── config.yaml
    ├── rke2-pss.yaml
    └── rke2.yaml
2 directories, 4 files


cat /etc/rancher/node/password
5b7715f905eef19bdcad53966d56837e

cat /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
debug: true
cni: canal
bind-address: 192.168.10.11
advertise-address: 192.168.10.11
node-ip: 192.168.10.11
disable-cloud-controller: true
disable:
  - servicelb
  - rke2-coredns-autoscaler
  - rke2-ingress-nginx
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook


cat /etc/rancher/rke2/rke2-pss.yaml 
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1beta1
    kind: PodSecurityConfiguration
    defaults:
      enforce: "privileged"
      enforce-version: "latest"
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces: []


tree /var/lib/rancher/rke2/bin/
/var/lib/rancher/rke2/bin/
├── containerd
├── containerd-shim-runc-v2
├── crictl
├── ctr
├── kubectl
├── kubelet
└── runc
0 directories, 7 files

# 심볼링 링크 생성
ln -s /var/lib/rancher/rke2/bin/containerd /usr/local/bin/containerd
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
ln -s /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl
ln -s /var/lib/rancher/rke2/bin/runc /usr/local/bin/runc
ln -s /var/lib/rancher/rke2/bin/ctr /usr/local/bin/ctr
ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml

# 버전 확인
runc --version
runc version 1.4.0

# 버전 확인
containerd --version
containerd github.com/k3s-io/containerd v2.1.5-k3s1 e77c15f30e5162d6abab671b0d74ca2243e2916e

# 버전 확인
kubectl version
Client Version: v1.33.7+rke2r3
Kustomize Version: v5.6.0
Server Version: v1.33.7+rke2r3

# 자동 완성
source <(kubectl completion bash)
alias k=kubectl
complete -F __start_kubectl k
echo 'source <(kubectl completion bash)' >> /etc/profile
echo 'alias k=kubectl' >> /etc/profile
echo 'complete -F __start_kubectl k' >> /etc/profile

k9s

# 파드 조회
k cluster-info -v=6
I0217 21:07:12.052897   12635 loader.go:402] Config loaded from file:  /root/.kube/config
Kubernetes control plane is running at https://192.168.10.11:6443

# 노드 조회
k get node -owide
k8s-node1   Ready    control-plane,etcd,master   4m32s   v1.33.7+rke2r3   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1

# 헬름 차트 조회
helm list -A
NAME                    NAMESPACE       REVISION        UPDATED                                      STATUS          CHART                                   APP VERSION
rke2-canal              kube-system     1               2026-02-17 12:03:23.339556117 +0000 UTC      deployed        rke2-canal-v3.31.3-build2026011900      v3.31.3    
rke2-coredns            kube-system     1               2026-02-17 12:03:23.33995216 +0000 UTC       deployed        rke2-coredns-1.45.008                   1.13.1     
rke2-metrics-server     kube-system     1               2026-02-17 12:03:48.249719598 +0000 UTC      deployed        rke2-metrics-server-3.13.006            0.8.0      
rke2-runtimeclasses     kube-system     1               2026-02-17 12:03:51.25648424 +0000 UTC       deployed        rke2-runtimeclasses-0.1.000             0.1.0 

# 파드 조회
kubectl get pod -A
NAMESPACE     NAME                                         READY   STATUS      RESTARTS   AGE
kube-system   etcd-k8s-node1                               1/1     Running     0          4m50s
kube-system   helm-install-rke2-canal-j6hc9                0/1     Completed   0          4m43s
kube-system   helm-install-rke2-coredns-frff5              0/1     Completed   0          4m43s
kube-system   helm-install-rke2-metrics-server-tv5gg       0/1     Completed   0          4m43s
kube-system   helm-install-rke2-runtimeclasses-cbppm       0/1     Completed   0          4m43s
kube-system   kube-apiserver-k8s-node1                     1/1     Running     0          4m50s
kube-system   kube-controller-manager-k8s-node1            1/1     Running     0          4m48s
kube-system   kube-proxy-k8s-node1                         1/1     Running     0          4m50s
kube-system   kube-scheduler-k8s-node1                     1/1     Running     0          4m48s
kube-system   rke2-canal-2bg9p                             2/2     Running     0          4m36s
kube-system   rke2-coredns-rke2-coredns-799c79bfc5-5pp5w   1/1     Running     0          4m36s
kube-system   rke2-metrics-server-6d59dd87df-l6djd         1/1     Running     0          4m11s


tree /var/lib/rancher/rke2 -L 1
/var/lib/rancher/rke2
├── agent
├── bin -> /var/lib/rancher/rke2/data/v1.33.7-rke2r3-57124bb8b02e/bin
├── data
└── server
4 directories, 0 files

# 서버 디렉토리 확인
# kubeconfig, 토큰, 인증서, 헬름 차트 by helm contoroller 등이 위치
tree /var/lib/rancher/rke2/server/
tree /var/lib/rancher/rke2/server/ -L 1
/var/lib/rancher/rke2/server/
├── agent-token -> /var/lib/rancher/rke2/server/token
├── cred
├── db
├── etc
├── manifests
├── node-token -> /var/lib/rancher/rke2/server/token
├── tls
└── token
5 directories, 3 files

ls -l /var/lib/rancher/rke2/server/
lrwxrwxrwx. 1 root root   34 Feb 17 21:02 agent-token -> /var/lib/rancher/rke2/server/token
drwx------. 2 root root 4096 Feb 17 21:02 cred
drwx------. 4 root root   35 Feb 17 21:03 db
drwx------. 2 root root   66 Feb 17 21:02 etc
drwxr-xr-x. 2 root root  180 Feb 17 21:03 manifests
lrwxrwxrwx. 1 root root   34 Feb 17 21:02 node-token -> /var/lib/rancher/rke2/server/token
drwx------. 6 root root 4096 Feb 17 21:02 tls
-rw-------. 1 root root  109 Feb 17 21:02 token

# 향후 노드 조인 시 사용할 토큰 확인
cat /var/lib/rancher/rke2/server/node-token
K104d73fa0b4bbbc74c6c494b5a7ca429d53f52d1759ee445fa666e1639091ff21a::server:a7b3bcfdb9be778d40dc9645cdc3e64c
cat /var/lib/rancher/rke2/server/token
K104d73fa0b4bbbc74c6c494b5a7ca429d53f52d1759ee445fa666e1639091ff21a::server:a7b3bcfdb9be778d40dc9645cdc3e64c


cat /var/lib/rancher/rke2/server/manifests/rke2-coredns.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  annotations:
    helm.cattle.io/chart-url: https://rke2-charts.rancher.io/assets/rke2-coredns/rke2-coredns-1.45.008.tgz
    rke2.cattle.io/inject-cluster-config: "true"
  name: rke2-coredns
  namespace: kube-system
spec:
  bootstrap: true
  chartContent: H4....
  set:
    global.clusterCIDR: 10.42.0.0/16
    global.clusterCIDRv4: 10.42.0.0/16
    global.clusterDNS: 10.43.0.10
    global.clusterDomain: cluster.local
    global.rke2DataDir: /var/lib/rancher/rke2
    global.serviceCIDR: 10.43.0.0/16
    global.systemDefaultIngressClass: ingress-nginx

# helm controller 및 addons 확인
kubectl get crd | grep -E 'helm|addon'
addons.k3s.cattle.io                                    2026-02-17T12:03:11Z
helmchartconfigs.helm.cattle.io                         2026-02-17T12:03:11Z
helmcharts.helm.cattle.io                               2026-02-17T12:03:11Z

kubectl get helmcharts.helm.cattle.io -n kube-system -owide
NAME                  REPO   CHART   VERSION   TARGETNAMESPACE   BOOTSTRAP   FAILED   JOB
rke2-canal                                                       true        False    helm-install-rke2-canal
rke2-coredns                                                     true        False    helm-install-rke2-coredns
rke2-metrics-server                                                          False    helm-install-rke2-metrics-server
rke2-runtimeclasses                                                          False    helm-install-rke2-runtimeclasses

kubectl get job -n kube-system
NAME                               STATUS     COMPLETIONS   DURATION   AGE
helm-install-rke2-canal            Complete   1/1           10s        7m35s
helm-install-rke2-coredns          Complete   1/1           9s         7m35s
helm-install-rke2-metrics-server   Complete   1/1           35s        7m35s
helm-install-rke2-runtimeclasses   Complete   1/1           38s        7m35s

kubectl get helmchartconfigs -n kube-system
rke2-canal     7m46s
rke2-coredns   7m46s

kubectl describe helmchartconfigs -n kube-system rke2-canal
Spec:
  Failure Policy:  reinstall
  Values Content:  flannel:
  iface: "enp0s9"

kubectl get addons.k3s.cattle.io -n kube-system
NAME                  SOURCE                                                            CHECKSUM
rke2-canal            /var/lib/rancher/rke2/server/manifests/rke2-canal.yaml            220100750c28ee364bdc90a15ac88bca04cc180482f16abe96dadfdbd16d8797
rke2-canal-config     /var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml     122823431e18d9f23621508c24bff9aff307f46b4d6d9208bbbbf23311db058e
rke2-coredns          /var/lib/rancher/rke2/server/manifests/rke2-coredns.yaml          e59de0862fdb5a5ca63502ce5a1554836c7fa433df5da1edd38e762fd3f038e8
rke2-coredns-config   /var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml   9c8e2bbb7603c69c233c9343c516d3d302fd59b758e2e7084c7ab08b5bfba0e4
rke2-metrics-server   /var/lib/rancher/rke2/server/manifests/rke2-metrics-server.yaml   040174dcf40f4e9670957ada86c179bcd4053fd31542be110808434a13108fa9
rke2-runtimeclasses   /var/lib/rancher/rke2/server/manifests/rke2-runtimeclasses.yaml   8a0e5f6ccda6be52151715569d2c7b384d0c5efb080ce5acc1412e5e376debf1

# 인증서 파일
cat /var/lib/rancher/rke2/server/tls/server-ca.crt | openssl x509 -text -noout 
cat /var/lib/rancher/rke2/server/tls/serving-kube-apiserver.crt | openssl x509 -text -noout 
        Issuer: CN=rke2-server-ca@1771329750
        Validity
            Not Before: Feb 17 12:02:30 2026 GMT
            Not After : Feb 17 12:02:30 2027 GMT
        Subject: CN=kube-apiserver
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage: 
                TLS Web Server Authentication
            X509v3 Authority Key Identifier: 
                9C:8E:FD:BE:A3:84:13:02:6B:AB:E6:78:DB:D4:78:D1:41:97:95:C0
            X509v3 Subject Alternative Name: 
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:localhost, DNS:k8s-node1, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1, IP Address:192.168.10.11, IP Address:192.168.10.11, IP Address:10.43.0.1

# bin 및 charts 디렉토리 확인
tree /var/lib/rancher/rke2/data/ -L 2
/var/lib/rancher/rke2/data/
└── v1.33.7-rke2r3-57124bb8b02e
    ├── bin
    └── charts
3 directories, 0 files

tree /var/lib/rancher/rke2/data/
/var/lib/rancher/rke2/data/
└── v1.33.7-rke2r3-57124bb8b02e
    ├── bin
    │   ├── containerd
    │   ├── containerd-shim-runc-v2
    │   ├── crictl
    │   ├── ctr
    │   ├── kubectl
    │   ├── kubelet
    │   └── runc
    └── charts
        ├── harvester-cloud-provider.yaml
        ├── harvester-csi-driver.yaml
        ├── rancher-vsphere-cpi.yaml
        ├── rancher-vsphere-csi.yaml
        ├── rke2-calico-crd.yaml
        ├── rke2-calico.yaml
        ├── rke2-canal.yaml
        ├── rke2-cilium.yaml
        ├── rke2-coredns.yaml
        ├── rke2-flannel.yaml
        ├── rke2-ingress-nginx.yaml
        ├── rke2-metrics-server.yaml
        ├── rke2-multus.yaml
        ├── rke2-runtimeclasses.yaml
        ├── rke2-snapshot-controller-crd.yaml
        ├── rke2-snapshot-controller.yaml
        ├── rke2-snapshot-validation-webhook.yaml
        ├── rke2-traefik-crd.yaml
        └── rke2-traefik.yaml
3 directories, 26 files


cat /var/lib/rancher/rke2/data/v1.33.7-rke2r3-57124bb8b02e/charts/rke2-coredns.yaml 
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: "rke2-coredns"
  namespace: "kube-system"
  annotations:
    helm.cattle.io/chart-url: "https://rke2-charts.rancher.io/assets/rke2-coredns/rke2-coredns-1.45.008.tgz"
    rke2.cattle.io/inject-cluster-config: "true"
spec:
  bootstrap: true
  chartContent: ...

tree /var/lib/rancher/rke2/agent/ | more
/var/lib/rancher/rke2/agent/
├── client-ca.crt
├── client-kubelet.crt
├── client-kubelet.key
├── client-kube-proxy.crt
├── client-kube-proxy.key
├── client-rke2-controller.crt
├── client-rke2-controller.key
├── containerd
│   ├── bin
│   ├── containerd.log
│   ├── io.containerd.content.v1.content
│   │   ├── blobs
│   │   └── ingest
│   ├── io.containerd.grpc.v1.cri
│   │   ├── containers
│   │   └── sandboxes
│   ├── io.containerd.grpc.v1.introspection
│   │   └── uuid
│   ├── io.containerd.metadata.v1.bolt
│   │   └── meta.db
│   ├── io.containerd.runtime.v2.task
│   │   └── k8s.io
│   ├── io.containerd.sandbox.controller.v1.shim
│   ├── io.containerd.snapshotter.v1.blockfile
│   ├── io.containerd.snapshotter.v1.btrfs
│   ├── io.containerd.snapshotter.v1.erofs
│   ├── io.containerd.snapshotter.v1.fuse-overlayfs
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.native
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.overlayfs
│   │   ├── metadata.db
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.stargz
│   │   ├── snapshotter
│   │   └── stargz
│   ├── lib
│   └── tmpmounts
├── etc
│   ├── containerd
│   │   └── config.toml
│   ├── crictl.yaml
│   └── kubelet.conf.d
│       └── 00-rke2-defaults.conf
├── images
│   ├── etcd-image.txt
│   ├── kube-apiserver-image.txt
│   ├── kube-controller-manager-image.txt
│   ├── kube-proxy-image.txt
│   ├── kube-scheduler-image.txt
│   └── runtime-image.txt
├── kubelet.kubeconfig
├── kubeproxy.kubeconfig
├── logs
│   └── kubelet.log
├── pod-manifests
│   ├── etcd.yaml
│   ├── kube-apiserver.yaml
│   ├── kube-controller-manager.yaml
│   ├── kube-proxy.yaml
│   └── kube-scheduler.yaml
├── rke2controller.kubeconfig
├── server-ca.crt
├── serving-kubelet.crt
└── serving-kubelet.key
33 directories, 32 files

crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                      ATTEMPT             POD ID              POD                                          NAMESPACE
6ecf971bba29e       46cb9a5fcbc54       10 minutes ago      Running             coredns                   0                   332307aeb30e8       rke2-coredns-rke2-coredns-799c79bfc5-5pp5w   kube-system
472ed5af9698d       de8d572a38bd5       10 minutes ago      Running             metrics-server            0                   b55cbea4845e6       rke2-metrics-server-6d59dd87df-l6djd         kube-system
200cd631ce228       06268f7737ab5       10 minutes ago      Running             kube-flannel              0                   75170d54af34f       rke2-canal-2bg9p                             kube-system
73f076e87a08a       0f7eeb2988536       10 minutes ago      Running             calico-node               0                   75170d54af34f       rke2-canal-2bg9p                             kube-system
6b8d36d633a9a       9b1fd4747a323       11 minutes ago      Running             kube-scheduler            0                   ac27d2da9b982       kube-scheduler-k8s-node1                     kube-system
c469de0e532cd       9b1fd4747a323       11 minutes ago      Running             kube-controller-manager   0                   0a489b382d232       kube-controller-manager-k8s-node1            kube-system
c45256e17825a       9b1fd4747a323       11 minutes ago      Running             kube-apiserver            0                   a0eb4e94c04c0       kube-apiserver-k8s-node1                     kube-system
251270bb41d42       45d834c35b2c8       11 minutes ago      Running             etcd                      0                   6e582b0bf6fd4       etcd-k8s-node1                               kube-system
c5fe2cf5b8ed0       9b1fd4747a323       11 minutes ago      Running             kube-proxy                0                   93ea8a186793d       kube-proxy-k8s-node1                         kube-system

# k3s가 포함되어잇는 것을 알수가 잇다.
cat /var/lib/rancher/rke2/agent/etc/crictl.yaml
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock

# 링크
ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml
crictl ps

crictl images
IMAGE                                           TAG                            IMAGE ID            SIZE
docker.io/rancher/hardened-calico               v3.31.3-build20260119          0f7eeb2988536       217MB
docker.io/rancher/hardened-coredns              v1.14.1-build20260116          46cb9a5fcbc54       27.2MB
docker.io/rancher/hardened-etcd                 v3.5.26-k3s1-build20260126     45d834c35b2c8       17.1MB
docker.io/rancher/hardened-flannel              v0.28.0-build20260119          06268f7737ab5       19.8MB
docker.io/rancher/hardened-k8s-metrics-server   v0.8.0-build20260116           de8d572a38bd5       19.4MB
docker.io/rancher/hardened-kubernetes           v1.33.7-rke2r3-build20260127   9b1fd4747a323       196MB
docker.io/rancher/klipper-helm                  v0.9.12-build20251215          e7ae0a941e9f4       60.9MB
docker.io/rancher/mirrored-pause                3.6                            7d46a07936af9       253kB
docker.io/rancher/rke2-runtime                  v1.33.7-rke2r3                 d32a726263ff6       91.3MB


# containerd 설정 파일 확인
# 직접 수정 비권장. 왜냐면 rke2에 의해 관리되기 때문
cat /var/lib/rancher/rke2/agent/etc/containerd/config.toml
# File generated by rke2. DO NOT EDIT. Use config.toml.tmpl instead.
version = 3
root = "/var/lib/rancher/rke2/agent/containerd"
state = "/run/k3s/containerd"
[grpc]
  address = "/run/k3s/containerd/containerd.sock"
[plugins.'io.containerd.internal.v1.opt']
  path = "/var/lib/rancher/rke2/agent/containerd"
[plugins.'io.containerd.grpc.v1.cri']
  stream_server_address = "127.0.0.1"
  stream_server_port = "10010"
[plugins.'io.containerd.cri.v1.runtime']
  enable_selinux = true
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  device_ownership_from_security_context = false
[plugins.'io.containerd.cri.v1.images']
  snapshotter = "overlayfs"
  disable_snapshot_annotations = true
  use_local_image_pull = true
[plugins.'io.containerd.cri.v1.images'.pinned_images]
  sandbox = "index.docker.io/rancher/mirrored-pause:3.6"
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runhcs-wcow-process]
  runtime_type = "io.containerd.runhcs.v1"
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'crun']
  runtime_type = "io.containerd.runc.v2"
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'crun'.options]
  BinaryName = "/usr/bin/crun"
  SystemdCgroup = true
[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = "/var/lib/rancher/rke2/agent/etc/containerd/certs.d"


ls -l /var/lib/rancher/rke2/agent/etc/containerd/certs.d
ls: cannot access '/var/lib/rancher/rke2/agent/etc/containerd/certs.d': No such file or directory

# 이미지 정보 확인
grep -H '' /var/lib/rancher/rke2/agent/images/*
/var/lib/rancher/rke2/agent/images/etcd-image.txt:index.docker.io/rancher/hardened-etcd:v3.5.26-k3s1-build20260126
/var/lib/rancher/rke2/agent/images/kube-apiserver-image.txt:index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
/var/lib/rancher/rke2/agent/images/kube-controller-manager-image.txt:index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
/var/lib/rancher/rke2/agent/images/kube-proxy-image.txt:index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
/var/lib/rancher/rke2/agent/images/kube-scheduler-image.txt:index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
/var/lib/rancher/rke2/agent/images/runtime-image.txt:index.docker.io/rancher/rke2-runtime:v1.33.7-rke2r3

crictl images
IMAGE                                           TAG                            IMAGE ID            SIZE
docker.io/rancher/hardened-calico               v3.31.3-build20260119          0f7eeb2988536       217MB
docker.io/rancher/hardened-coredns              v1.14.1-build20260116          46cb9a5fcbc54       27.2MB
docker.io/rancher/hardened-etcd                 v3.5.26-k3s1-build20260126     45d834c35b2c8       17.1MB
docker.io/rancher/hardened-flannel              v0.28.0-build20260119          06268f7737ab5       19.8MB
docker.io/rancher/hardened-k8s-metrics-server   v0.8.0-build20260116           de8d572a38bd5       19.4MB
docker.io/rancher/hardened-kubernetes           v1.33.7-rke2r3-build20260127   9b1fd4747a323       196MB
docker.io/rancher/klipper-helm                  v0.9.12-build20251215          e7ae0a941e9f4       60.9MB
docker.io/rancher/mirrored-pause                3.6                            7d46a07936af9       253kB
docker.io/rancher/rke2-runtime                  v1.33.7-rke2r3                 d32a726263ff6       91.3MB

# kubelet 설정 파일 확인
cat /var/lib/rancher/rke2/agent/etc/kubelet.conf.d/00-rke2-defaults.conf
address: 192.168.10.11
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /var/lib/rancher/rke2/agent/client-ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: systemd
clusterDNS:
- 10.43.0.10
clusterDomain: cluster.local
containerRuntimeEndpoint: unix:///run/k3s/containerd/containerd.sock
cpuManagerReconcilePeriod: 10s
crashLoopBackOff: {}
evictionHard:
  imagefs.available: 5%
  nodefs.available: 5%
evictionMinimumReclaim:
  imagefs.available: 10%
  nodefs.available: 10%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: false
fileCheckFrequency: 20s
healthzBindAddress: 127.0.0.1
httpCheckFrequency: 20s
imageMaximumGCAge: 0s
imageMinimumGCAge: 2m0s
kind: KubeletConfiguration
logging:
  flushFrequency: 5s
  format: text
  options:
    json:
      infoBufferSize: "0"
    text:
      infoBufferSize: "0"
  verbosity: 0
memorySwap: {}
nodeStatusReportFrequency: 5m0s
nodeStatusUpdateFrequency: 10s
resolvConf: /etc/resolv.conf
runtimeRequestTimeout: 2m0s
serializeImagePulls: false
shutdownGracePeriod: 0s
shutdownGracePeriodCriticalPods: 0s
# 스태틱 파드 경로 위치
staticPodPath: /var/lib/rancher/rke2/agent/pod-manifests
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
tlsCertFile: /var/lib/rancher/rke2/agent/serving-kubelet.crt
tlsPrivateKeyFile: /var/lib/rancher/rke2/agent/serving-kubelet.key
volumeStatsAggPeriod: 1m0s

# kubelet 로그 확인
tail -f /var/lib/rancher/rke2/agent/logs/kubelet.log

# kubelet이 관리하는 static pod 매니페스트 확인
tree /var/lib/rancher/rke2/agent/pod-manifests
/var/lib/rancher/rke2/agent/pod-manifests
├── etcd.yaml
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
├── kube-proxy.yaml
└── kube-scheduler.yaml
0 directories, 5 files

# kube-apiserver 매니페스트 확인
kubectl describe pod -n kube-system kube-apiserver-k8s-node1
Containers:
  kube-apiserver:
    Container ID:  containerd://c45256e17825ad71c3e21d580bf246ea4803bb4916042f4ac82394a977135abb
    Image:         index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
    Image ID:      docker.io/rancher/hardened-kubernetes@sha256:35e51591731ad3279e5f79c8ca3f83c8055b19ae9ca16f83bbdc7f0d7a3ffa2a
    Port:          6443/TCP
    Host Port:     6443/TCP
    Command:
      kube-apiserver
    Args:
      --admission-control-config-file=/etc/rancher/rke2/rke2-pss.yaml
      --advertise-address=192.168.10.11
      --allow-privileged=true
      --anonymous-auth=false
      --api-audiences=https://kubernetes.default.svc.cluster.local,rke2
      --authorization-mode=Node,RBAC
      --bind-address=0.0.0.0
      --cert-dir=/var/lib/rancher/rke2/server/tls/temporary-certs
      --client-ca-file=/var/lib/rancher/rke2/server/tls/client-ca.crt
      --egress-selector-config-file=/var/lib/rancher/rke2/server/etc/egress-selector-config.yaml
      --enable-admission-plugins=NodeRestriction
      --enable-aggregator-routing=true
      --enable-bootstrap-token-auth=true
      # etcd 암호화 위치 
      --encryption-provider-config=/var/lib/rancher/rke2/server/cred/encryption-config.json
      --encryption-provider-config-automatic-reload=true
      # etcd 인증서
      --etcd-cafile=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt
      --etcd-certfile=/var/lib/rancher/rke2/server/tls/etcd/client.crt
      --etcd-keyfile=/var/lib/rancher/rke2/server/tls/etcd/client.key
      --etcd-servers=https://127.0.0.1:2379
      # kubelet 인증서
      --kubelet-certificate-authority=/var/lib/rancher/rke2/server/tls/server-ca.crt
      --kubelet-client-certificate=/var/lib/rancher/rke2/server/tls/client-kube-apiserver.crt
      --kubelet-client-key=/var/lib/rancher/rke2/server/tls/client-kube-apiserver.key
      --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
      --profiling=false
      --proxy-client-cert-file=/var/lib/rancher/rke2/server/tls/client-auth-proxy.crt
      --proxy-client-key-file=/var/lib/rancher/rke2/server/tls/client-auth-proxy.key
      --requestheader-allowed-names=system:auth-proxy
      --requestheader-client-ca-file=/var/lib/rancher/rke2/server/tls/request-header-ca.crt
      --requestheader-extra-headers-prefix=X-Remote-Extra-
      --requestheader-group-headers=X-Remote-Group
      --requestheader-username-headers=X-Remote-User
      --secure-port=6443
      --service-account-issuer=https://kubernetes.default.svc.cluster.local
      --service-account-key-file=/var/lib/rancher/rke2/server/tls/service.key
      --service-account-signing-key-file=/var/lib/rancher/rke2/server/tls/service.current.key
      --service-cluster-ip-range=10.43.0.0/16
      --service-node-port-range=30000-32767
      --storage-backend=etcd3
      --tls-cert-file=/var/lib/rancher/rke2/server/tls/serving-kube-apiserver.crt
      --tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      --tls-private-key-file=/var/lib/rancher/rke2/server/tls/serving-kube-apiserver.key

# etcd encryption 설정 파일 확인, 기본 활성화되어잇음
cat /var/lib/rancher/rke2/server/cred/encryption-config.json | jq
{
  "kind": "EncryptionConfiguration",
  "apiVersion": "apiserver.config.k8s.io/v1",
  "resources": [
    {
      "resources": [
        "secrets"
      ],
      "providers": [
        {
          "aescbc": {
            "keys": [
              {
                "name": "aescbckey",
                "secret": "ME9EqzkexUb/I6B/9/NG0BFmg2GIv7HfYiqv+e+NI2Q="
              }
            ]
          }
        },
        {
          "identity": {}
        }
      ]
    }
  ]
}


# 보안을 위해 디렉토리가 아닌 파일 형태로 마운트 되어잇는 것을 알 수 있다.
kubectl describe pod -n kube-system etcd-k8s-node1
Volumes:
  dir0:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/db/etcd
    HostPathType:  DirectoryOrCreate
  file0:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/server-client.crt
    HostPathType:  File
  file1:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/server-client.key
    HostPathType:  File
  file2:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt
    HostPathType:  File
  file3:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.crt
    HostPathType:  File
  file4:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.key
    HostPathType:  File
  file5:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/tls/etcd/peer-ca.crt
    HostPathType:  File
  file6:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rancher/rke2/server/db/etcd/config
    HostPathType:  File

# etcd 매니페스트 확인
cat /var/lib/rancher/rke2/agent/pod-manifests/etcd.yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    etcd.k3s.io/initial: '{"initial-advertise-peer-urls":"https://192.168.10.11:2380","initial-cluster":"k8s-node1-edb7e47e=https://192.168.10.11:2380","initial-cluster-state":"new"}'
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
  uid: 76238339541a86d5625c6933933e00a9
spec:
  containers:
  - args:
    - --config-file=/var/lib/rancher/rke2/server/db/etcd/config
    command:
    - etcd
    env:
    - name: FILE_HASH
      value: 117f2228f03cbb7f2ecd804d8ff90365f2ea66acc779d80785ff6ff7bd6c73b6
    - name: NO_PROXY
      value: .svc,.cluster.local,10.42.0.0/16,10.43.0.0/16
    image: index.docker.io/rancher/hardened-etcd:v3.5.26-k3s1-build20260126
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: localhost
        path: /health?serializable=true
        port: 2381
        scheme: HTTP
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: etcd
    ports:
    - containerPort: 2379
      name: client
      protocol: TCP
    - containerPort: 2380
      name: peer
      protocol: TCP
    - containerPort: 2381
      name: metrics
      protocol: TCP
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
    securityContext:
      privileged: false
    volumeMounts:
    - mountPath: /var/lib/rancher/rke2/server/db/etcd
      name: dir0
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/server-client.crt
      name: file0
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/server-client.key
      name: file1
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt
      name: file2
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.crt
      name: file3
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.key
      name: file4
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/tls/etcd/peer-ca.crt
      name: file5
      readOnly: true
    - mountPath: /var/lib/rancher/rke2/server/db/etcd/config
      name: file6
      readOnly: true
  hostNetwork: true
  priorityClassName: system-cluster-critical
  securityContext:
    seLinuxOptions:
      type: rke2_service_db_t
  volumes:
  - hostPath:
      path: /var/lib/rancher/rke2/server/db/etcd
      type: DirectoryOrCreate
    name: dir0
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/server-client.crt
      type: File
    name: file0
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/server-client.key
      type: File
    name: file1
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt
      type: File
    name: file2
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.crt
      type: File
    name: file3
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/peer-server-client.key
      type: File
    name: file4
  - hostPath:
      path: /var/lib/rancher/rke2/server/tls/etcd/peer-ca.crt
      type: File
    name: file5
  - hostPath:
      path: /var/lib/rancher/rke2/server/db/etcd/config
      type: File
    name: file6
status: {}

# etcdctl 바이너리 위치 확인
find / -name etcdctl 2>/dev/null
/run/k3s/containerd/io.containerd.runtime.v2.task/k8s.io/251270bb41d42f78c81c4bbfc20ca3052cec069fb0f8afce9fc16bd61cefaf5f/rootfs/usr/local/bin/etcdctl
/var/lib/rancher/rke2/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/fs/usr/local/bin/etcdctl

ln -s /var/lib/rancher/rke2/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/fs/usr/local/bin/etcdctl /usr/local/bin/etcdctl

etcdctl version
etcdctl version: 3.5.26
API version: 3.5

etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/client.key \
  endpoint status --write-out=table
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|        ENDPOINT        |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| https://127.0.0.1:2379 | 6571fb7574e87dba |  3.5.26 |  7.2 MB |      true |      false |         2 |       4006 |               4006 |        |
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

# kube-scheduler 매니페스트 확인
kubectl describe pod -n kube-system kube-scheduler-k8s-node1
cat /var/lib/rancher/rke2/agent/pod-manifests/kube-scheduler.yaml

# kube-controller-manager 매니페스트 확인
# 기본적으로 설정된 튜닝
cat /var/lib/rancher/rke2/agent/pod-manifests/kube-controller-manager.yaml
spec:
  containers:
  - args:
    # 여러 서비스가 동일한 포트 공유 허용 여부 설정
    - --permit-port-sharing=true
    # 플렉스 볼륨 플러그인이 추가로 서드파티 볼륨 플러그인을 검색해야 하는 디렉터리의 경로
    # 지원중단인데 왜 존재하는지 이해가 안간다.
    - --flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins
    # 완료된 Pod가 1000개 이상 쌓이면 자동 정리(GC), 파드 로그/히스토리 과도 누적 방지
    - --terminated-pod-gc-threshold=1000
    # 각 노드의 파드 CIDR 자동할당
    - --allocate-node-cidrs=true
    - --authentication-kubeconfig=/var/lib/rancher/rke2/server/cred/controller.kubeconfig
    - --authorization-kubeconfig=/var/lib/rancher/rke2/server/cred/controller.kubeconfig
    - --bind-address=127.0.0.1
    - --cluster-cidr=10.42.0.0/16
    #  --cluster-signing-*: Kubelet이 서버 인증서를 요청하거나, API 서버 클라이언트가 인증서를 요청할 때 어떤 CA 키와 인증서로 서명해줄지 지정한다.
    - --cluster-signing-kube-apiserver-client-cert-file=/var/lib/rancher/rke2/server/tls/client-ca.nochain.crt
    - --cluster-signing-kube-apiserver-client-key-file=/var/lib/rancher/rke2/server/tls/client-ca.key
    - --cluster-signing-kubelet-client-cert-file=/var/lib/rancher/rke2/server/tls/client-ca.nochain.crt
    - --cluster-signing-kubelet-client-key-file=/var/lib/rancher/rke2/server/tls/client-ca.key
    - --cluster-signing-kubelet-serving-cert-file=/var/lib/rancher/rke2/server/tls/server-ca.nochain.crt
    - --cluster-signing-kubelet-serving-key-file=/var/lib/rancher/rke2/server/tls/server-ca.key
    - --cluster-signing-legacy-unknown-cert-file=/var/lib/rancher/rke2/server/tls/server-ca.nochain.crt
    - --cluster-signing-legacy-unknown-key-file=/var/lib/rancher/rke2/server/tls/server-ca.key
    # 컨트롤러 활성화 여부 
    - --controllers=*,tokencleaner
    - --kubeconfig=/var/lib/rancher/rke2/server/cred/controller.kubeconfig
    # 프로파일링 비활성화
    - --profiling=false
    # 서비스 계정(Service Account) 토큰 등을 검증할 때 사용할 루트 인증서입니다.
    - --root-ca-file=/var/lib/rancher/rke2/server/tls/server-ca.crt
    - --secure-port=10257
     # Pod 내에서 API 서버와 통신할 때 사용하는 **서비스 계정 토큰(JWT)**을 생성하고 서명하는 데 사용되는 키입니다.
    - --service-account-private-key-file=/var/lib/rancher/rke2/server/tls/service.current.key
    - --service-cluster-ip-range=10.43.0.0/16
    - --tls-cert-file=/var/lib/rancher/rke2/server/tls/kube-controller-manager/kube-controller-manager.crt
    - --tls-private-key-file=/var/lib/rancher/rke2/server/tls/kube-controller-manager/kube-controller-manager.key
    - --use-service-account-credentials=true

# kube-proxy 매니페스트 확인
cat /var/lib/rancher/rke2/agent/pod-manifests/kube-proxy.yaml
spec:
  containers:
  - args:
    # 파드 cidr 
    - --cluster-cidr=10.42.0.0/16
    # 코어당 conntrack 최대값 제한 없음, 대규모 트래픽 환경에서 NAT 테이블 부족 방지
    - --conntrack-max-per-core=0
    # ESTABLISHED 상태 timeout 무제한
    - --conntrack-tcp-timeout-close-wait=0s
    # CLOSE_WAIT 상태 timeout 무제한
    - --conntrack-tcp-timeout-established=0s
    - --healthz-bind-address=127.0.0.1
    - --hostname-override=k8s-node1
    - --kubeconfig=/var/lib/rancher/rke2/agent/kubeproxy.kubeconfig
    - --proxy-mode=iptables
```


### RKE2 워커 노드 추가 
```sh
# 서버(node1) 수행
# join 토큰 확인
cat /var/lib/rancher/rke2/server/node-token
K104d73fa0b4bbbc74c6c494b5a7ca429d53f52d1759ee445fa666e1639091ff21a::server:a7b3bcfdb9be778d40dc9645cdc3e64c

# RKE2 클러스터 조인 시 API 포트 확인
# 6443이 아닌 9345 포트를 사용해 관리한다.
ss -tnlp | grep 9345
LISTEN 0      4096   192.168.10.11:9345       0.0.0.0:*    users:(("rke2",pid=6474,fd=6))                          

vagrant ssh k8s-node2

# RKE2 에이전트 설치
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_CHANNEL=v1.33 sh -
TOKEN=K104d73fa0b4bbbc74c6c494b5a7ca429d53f52d1759ee445fa666e1639091ff21a::server:a7b3bcfdb9be778d40dc9645cdc3e64c

mkdir -p /etc/rancher/rke2/

# RKE2 에이전트 설정 파일 작성
cat << EOF > /etc/rancher/rke2/config.yaml
server: https://192.168.10.11:9345
token: $TOKEN
EOF

# 설정 확인
cat /etc/rancher/rke2/config.yaml

# RKE2 에이전트 서비스 시작
systemctl enable --now rke2-agent.service

journalctl -u rke2-agent -f
Feb 17 22:07:22 k8s-node2 rke2[6376]: time="2026-02-17T22:07:22+09:00" level=info msg="Tunnel authorizer set Kubelet Port 0.0.0.0:10250"

# 별다를게 없다.
tree /var/lib/rancher/rke2 -L 1
/var/lib/rancher/rke2
├── agent
├── bin -> /var/lib/rancher/rke2/data/v1.33.7-rke2r3-57124bb8b02e/bin
├── data
└── server
4 directories, 0 files

systemctl status rke2-agent.service --no-pager
● rke2-agent.service - Rancher Kubernetes Engine v2 (agent)
     Loaded: loaded (/usr/lib/systemd/system/rke2-agent.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-02-17 22:07:09 KST; 1min 58s ago

# 서비스 파일 확인
cat /usr/lib/systemd/system/rke2-agent.service
[Unit]
Description=Rancher Kubernetes Engine v2 (agent)
Documentation=https://github.com/rancher/rke2#readme
Wants=network-online.target
After=network-online.target
Conflicts=rke2-server.service

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/usr/lib/systemd/system/%N.env
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/rke2 agent
ExecStopPost=-/bin/sh -c "systemd-cgls /system.slice/%n | grep -Eo '[0-9]+ (containerd|kubelet)' | awk '{print $1}' | xargs -r kill"

pstree -al |grep rke2
  |-rke2
  |   |-containerd -c /var/lib/rancher/rke2/agent/etc/containerd/config.toml
  |   |-kubelet --volume-plugin-dir=/var/lib/kubelet/volumeplugins --file-check-frequency=5s --sync-frequency=30s --config-dir=/var/lib/rancher/rke2/agent/etc/kubelet.conf.d --containerd=/run/k3s/containerd/containerd.sock --hostname-override=k8s-node2 --kubeconfig=/var/lib/rancher/rke2/agent/kubelet.kubeconfig --node-labels= --read-only-port=0
  |   `-10*[{rke2}]

# 심볼링 링크 생성
ln -s /var/lib/rancher/rke2/bin/containerd /usr/local/bin/containerd
ln -s /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl
ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml

# cni 플러그인과 kube-proxy 컨테이너가 실행 중인 것 확인
crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                    NAMESPACE
4c26007ecdb2c       06268f7737ab5       3 minutes ago       Running             kube-flannel        0                   846422d2b3351       rke2-canal-v4shl       kube-system
293f688fd6c5a       0f7eeb2988536       3 minutes ago       Running             calico-node         0                   846422d2b3351       rke2-canal-v4shl       kube-system
ba1de96a3c026       9b1fd4747a323       3 minutes ago       Running             kube-proxy          0                   6883d85a58f98       kube-proxy-k8s-node2   kube-system

crictl images
IMAGE                                   TAG                            IMAGE ID            SIZE
docker.io/rancher/hardened-calico       v3.31.3-build20260119          0f7eeb2988536       217MB
docker.io/rancher/hardened-flannel      v0.28.0-build20260119          06268f7737ab5       19.8MB
docker.io/rancher/hardened-kubernetes   v1.33.7-rke2r3-build20260127   9b1fd4747a323       196MB
docker.io/rancher/mirrored-pause        3.6                            7d46a07936af9       253kB
docker.io/rancher/rke2-runtime          v1.33.7-rke2r3                 d32a726263ff6       91.3MB

tree /etc/rancher/
/etc/rancher/
├── node
│   └── password
└── rke2
    ├── config.yaml
    └── rke2-pss.yaml
2 directories, 3 files

tree /var/lib/rancher/rke2/agent/ -L 3
/var/lib/rancher/rke2/agent/
├── client-ca.crt
├── client-kubelet.crt
├── client-kubelet.key
├── client-kube-proxy.crt
├── client-kube-proxy.key
├── client-rke2-controller.crt
├── client-rke2-controller.key
├── containerd
│   ├── bin
│   ├── containerd.log
│   ├── io.containerd.content.v1.content
│   │   ├── blobs
│   │   └── ingest
│   ├── io.containerd.grpc.v1.cri
│   │   ├── containers
│   │   └── sandboxes
│   ├── io.containerd.grpc.v1.introspection
│   │   └── uuid
│   ├── io.containerd.metadata.v1.bolt
│   │   └── meta.db
│   ├── io.containerd.runtime.v2.task
│   │   └── k8s.io
│   ├── io.containerd.sandbox.controller.v1.shim
│   ├── io.containerd.snapshotter.v1.blockfile
│   ├── io.containerd.snapshotter.v1.btrfs
│   ├── io.containerd.snapshotter.v1.erofs
│   ├── io.containerd.snapshotter.v1.fuse-overlayfs
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.native
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.overlayfs
│   │   ├── metadata.db
│   │   └── snapshots
│   ├── io.containerd.snapshotter.v1.stargz
│   │   ├── snapshotter
│   │   └── stargz
│   ├── lib
│   └── tmpmounts
├── etc
│   ├── containerd
│   │   └── config.toml
│   ├── crictl.yaml
│   ├── kubelet.conf.d
│   │   └── 00-rke2-defaults.conf
│   ├── rke2-agent-load-balancer.json
│   └── rke2-api-server-agent-load-balancer.json
├── images
│   ├── kube-proxy-image.txt
│   └── runtime-image.txt
├── kubelet.kubeconfig
├── kubeproxy.kubeconfig
├── logs
│   └── kubelet.log
├── pod-manifests
│   └── kube-proxy.yaml
├── rke2controller.kubeconfig
├── server-ca.crt
├── serving-kubelet.crt
└── serving-kubelet.key
33 directories, 26 files

cat /var/lib/rancher/rke2/agent/etc/containerd/config.toml

cat /var/lib/rancher/rke2/agent/etc/kubelet.conf.d/00-rke2-defaults
address: 0.0.0.0
allowedUnsafeSysctls:
- net.ipv4.ip_forward
- net.ipv6.conf.all.forwarding

# RKE2 워커를 RKE2 서버와 통신하는 API 주소
cat /var/lib/rancher/rke2/agent/etc/rke2-agent-load-balancer.json  | jq
{
  "ServerURL": "https://192.168.10.11:9345",
  "ServerAddresses": [
    "192.168.10.11:9345"
  ]
}

# 컨트롤 플레인 apiserevr 주소
cat /var/lib/rancher/rke2/agent/etc/rke2-api-server-agent-load-balancer.json | jq
{
  "ServerURL": "https://192.168.10.11:6443",
  "ServerAddresses": [
    "192.168.10.11:6443"
  ]
}

cat /var/lib/rancher/rke2/agent/pod-manifests/kube-proxy.yaml

# k8s-node1
kubectl get node -owide
NAME        STATUS   ROLES                       AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
k8s-node1   Ready    control-plane,etcd,master   65m   v1.33.7+rke2r3   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
k8s-node2   Ready    <none>                      60s   v1.33.7+rke2r3   192.168.10.12   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1

kubectl get pod -n kube-system -owide | grep k8s-node2
kube-proxy-k8s-node2                         1/1     Running     0          70s   192.168.10.12   k8s-node2   <none>           <none>
rke2-canal-v4shl                             2/2     Running     0          70s   192.168.10.12   k8s-node2   <none>           <none>
```

### RKE 워커 노드 삭제 후 재 추가
```sh
# k8s-node1
# 워커 노드 드레인 및 삭제
kubectl drain k8s-node2 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-node2

# k8s-node2
systemctl stop rke2-agent

ls -l /usr/bin/rke2*
cat /usr/bin/rke2-uninstall.sh
rke2-uninstall.sh

tree /etc/rancher
/etc/rancher [error opening dir]

tree /var/lib/rancher
/etc/rancher [error opening dir]

# k8s-node2
# 재추가 
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_CHANNEL=v1.33 sh -

mkdir -p /etc/rancher/rke2/

cat << EOF > /etc/rancher/rke2/config.yaml
server: https://192.168.10.11:9345
token: $TOKEN
EOF

cat /etc/rancher/rke2/config.yaml

systemctl enable --now rke2-agent.service

journalctl -u rke2-agent -

# 샘플 애플리케이션 배포
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webpod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webpod
  template:
    metadata:
      labels:
        app: webpod
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - sample-app
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: webpod
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: webpod
  labels:
    app: webpod
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30000
  type: NodePort
EOF

# 확인
kubectl get deploy,pod,svc,ep -owide
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES           SELECTOR
deployment.apps/webpod   2/2     2            2           9s    webpod       traefik/whoami   app=webpod
NAME                          READY   STATUS    RESTARTS   AGE   IP          NODE        NOMINATED NODE   READINESS GATES
pod/webpod-697b545f57-k5gtw   1/1     Running   0          9s    10.42.3.2   k8s-node2   <none>           <none>
pod/webpod-697b545f57-rxqbx   1/1     Running   0          9s    10.42.0.6   k8s-node1   <none>           <none>
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE   SELECTOR
service/kubernetes   ClusterIP   10.43.0.1     <none>        443/TCP        74m   <none>
service/webpod       NodePort    10.43.49.32   <none>        80:30000/TCP   9s    app=webpod
NAME                   ENDPOINTS                   AGE
endpoints/kubernetes   192.168.10.11:6443          74m
endpoints/webpod       10.42.0.6:80,10.42.3.2:80   9s

while true; do curl -s http://192.168.10.12:30000 | grep Hostname; date; sleep 1; done
```

### 인증서 관리
```sh
rke2 certificate --help
COMMANDS:
   check      Check rke2 component certificates on disk
   rotate     Rotate rke2 component certificates on disk
   rotate-ca  Write updated rke2 CA certificates to the datastore
   help, h    Shows a list of commands or help for one command

# server(node1)
# 인증서 상태 확인
rke2 certificate check --output table
INFO[0000] Server detected, checking agent and server certificates 
FILENAME                           SUBJECT                             USAGES                  EXPIRES                  RESIDUAL TIME   STATUS
--------                           -------                             ------                  -------                  -------------   ------
client-kube-proxy.crt              system:kube-proxy                   ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-kube-proxy.crt              rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-rke2-controller.crt         system:rke2-controller              ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-rke2-controller.crt         rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-kube-apiserver.crt          system:apiserver                    ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-kube-apiserver.crt          rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
serving-kube-apiserver.crt         kube-apiserver                      ServerAuth              Feb 17, 2027 12:02 UTC   1 year          OK
serving-kube-apiserver.crt         rke2-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-admin.crt                   system:admin                        ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-admin.crt                   rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-rke2-cloud-controller.crt   rke2-cloud-controller-manager       ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-rke2-cloud-controller.crt   rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client.crt                         etcd-client                         ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client.crt                         etcd-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
server-client.crt                  etcd-server                         ServerAuth,ClientAuth   Feb 17, 2027 12:02 UTC   1 year          OK
server-client.crt                  etcd-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
peer-server-client.crt             etcd-peer                           ServerAuth,ClientAuth   Feb 17, 2027 12:02 UTC   1 year          OK
peer-server-client.crt             etcd-peer-ca@1771329750             CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-scheduler.crt               system:kube-scheduler               ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-scheduler.crt               rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
kube-scheduler.crt                 kube-scheduler                      ServerAuth              Feb 17, 2027 12:02 UTC   1 year          OK
kube-scheduler.crt                 rke2-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-supervisor.crt              system:rke2-supervisor              ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-supervisor.crt              rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-kubelet.crt                 system:node:k8s-node1               ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-kubelet.crt                 rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
serving-kubelet.crt                k8s-node1                           ServerAuth              Feb 17, 2027 12:02 UTC   1 year          OK
serving-kubelet.crt                rke2-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-auth-proxy.crt              system:auth-proxy                   ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-auth-proxy.crt              rke2-request-header-ca@1771329750   CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
client-controller.crt              system:kube-controller-manager      ClientAuth              Feb 17, 2027 12:02 UTC   1 year          OK
client-controller.crt              rke2-client-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK
kube-controller-manager.crt        kube-controller-manager             ServerAuth              Feb 17, 2027 12:02 UTC   1 year          OK
kube-controller-manager.crt        rke2-server-ca@1771329750           CertSign                Feb 15, 2036 12:02 UTC   10 years        OK

# agent(node2)
rke2 certificate check --output table
INFO[0000] Server detected, checking agent and server certificates 
FILENAME                     SUBJECT                     USAGES       EXPIRES                  RESIDUAL TIME   STATUS
--------                     -------                     ------       -------                  -------------   ------
client-rke2-controller.crt   system:rke2-controller      ClientAuth   Feb 17, 2027 13:15 UTC   1 year          OK
client-rke2-controller.crt   rke2-client-ca@1771329750   CertSign     Feb 15, 2036 12:02 UTC   10 years        OK
client-kube-proxy.crt        system:kube-proxy           ClientAuth   Feb 17, 2027 13:15 UTC   1 year          OK
client-kube-proxy.crt        rke2-client-ca@1771329750   CertSign     Feb 15, 2036 12:02 UTC   10 years        OK
client-kubelet.crt           system:node:k8s-node2       ClientAuth   Feb 17, 2027 13:15 UTC   1 year          OK
client-kubelet.crt           rke2-client-ca@1771329750   CertSign     Feb 15, 2036 12:02 UTC   10 years        OK
serving-kubelet.crt          k8s-node2                   ServerAuth   Feb 17, 2027 13:15 UTC   1 year          OK
serving-kubelet.crt          rke2-server-ca@1771329750   CertSign     Feb 15, 2036 12:02 UTC   10 years        OK


## 인증서 수동 교체 
# k8s-node-1
systemctl stop rke2-server

rke2 certificate rotate
INFO[0000] Successfully backed up certificates to /var/lib/rancher/rke2/server/tls-1771335242, please restart rke2 server or agent to rotate certificates 

rke2 certificate check --output table
INFO[0000] Server detected, checking agent and server certificates 
FILENAME   SUBJECT   USAGES   EXPIRES   RESIDUAL TIME   STATUS
--------   -------   ------   -------   -------------   ------

systemctl start rke2-server

date -u
Tue Feb 17 01:36:27 PM UTC 2026

rke2 certificate check --output table
serving-kube-apiserver.crt         kube-apiserver                      ServerAuth              Feb 17, 2027 13:35 UTC   1 year          OK
...

# 인증서 교체 후 kubeconfig 파일 업데이트
diff /etc/rancher/rke2/rke2.yaml ~/.kube/config

yes | cp /etc/rancher/rke2/rke2.yaml ~/.kube/config ; echo

# 동작 확인
kubectl cluster-info
Kubernetes control plane is running at https://192.168.10.11:6443
```

### k8s 버전 수동 업그레이드
```sh
# 모니터링 도구 
while true; do curl -s http://192.168.10.12:30000 | grep Hostname; date; sleep 1; done
watch -d "kubectl get pod -n kube-system -owide --sort-by=.metadata.creationTimestamp | tac"
watch -d "kubectl get node"
watch -d etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/client.key \
  member list --write-out=table

# 노드 확인
kubectl get node
NAME        STATUS   ROLES                       AGE   VERSION
k8s-node1   Ready    control-plane,etcd,master   16h   v1.33.7+rke2r3
k8s-node2   Ready    <none>                      14h   v1.33.7+rke2r3

rke2 --version
rke2 version v1.33.7+rke2r3 (7e4fd1a82edf497cab91c220144619bbad659cf4)

# 업그레이 가능한 버전 확인
curl -s https://update.rke2.io/v1-release/channels | jq .data

# server(노드1)에서 업그레이드 진행
# 1.33 버전에서 1.34 버전으로 업그레이드 진행
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.34 sh -

kube-scheduler-k8s-node1                     0/1     Running
0          5s    192.168.10.11   k8s-node1   <none>           <none>
kube-controller-manager-k8s-node1            0/1     Running
0          6s    192.168.10.11   k8s-node1   <none>           <none>
kube-proxy-k8s-node1                         1/1     Running
0          46s   192.168.10.11   k8s-node1   <none>           <none>
etcd-k8s-node1                               1/1     Running
0          46s   192.168.10.11   k8s-node1   <none>           <none>
kube-apiserver-k8s-node1                     1/1     Running
0          46s   192.168.10.11   k8s-node1   <none>           <none>

# 기존 1.33 버전의 레포지토리 정보 삭제 확인 
dnf repolist
rancher-rke2-1.34-stable        Rancher RKE2 1.34 (v1.34)
rancher-rke2-common-stable      Rancher RKE2 Common (v1.34)

tree /etc/yum.repos.d/
/etc/yum.repos.d/
├── rancher-rke2.repo

# 기존 내역 1.33 버전이 아닌 1.34 버전으로 변경된 것을 확인
cat /etc/yum.repos.d/rancher-rke2.repo | grep -iE 'name|baseurl'
[rancher-rke2-common-stable]
name=Rancher RKE2 Common (v1.34)
baseurl=https://rpm.rancher.io/rke2/stable/common/centos/9/noarch
[rancher-rke2-1.34-stable]
name=Rancher RKE2 1.34 (v1.34)
baseurl=https://rpm.rancher.io/rke2/stable/1.34/centos/9/aarch64

# 이미지 확인
kubectl get pods -n kube-system -o custom-columns="POD_NAME:.metadata.name,IMAGES:.spec.containers[*].image"
POD_NAME                                     IMAGES
etcd-k8s-node1                               index.docker.io/rancher/hardened-etcd:v3.6.7-k3s1-build20260126
helm-install-rke2-canal-9d26c                rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-coredns-9jtnr              rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-metrics-server-7tht2       rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-runtimeclasses-9hgn5       rancher/klipper-helm:v0.9.14-build20260210
kube-apiserver-k8s-node1                     index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-controller-manager-k8s-node1            index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node1                         index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node2                         index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
kube-scheduler-k8s-node1                     index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
rke2-canal-7cfjk                             rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-canal-w4ltc                             rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-coredns-rke2-coredns-77f54456d4-s8jrv   rancher/hardened-coredns:v1.14.1-build20260206
rke2-metrics-server-69f4f95bf7-7nx6h         rancher/hardened-k8s-metrics-server:v0.8.1-build20260206

kubectl get pods -n kube-system \
  -o custom-columns=\
POD:.metadata.name,\
CONTAINERS:.spec.containers[*].name,\
IMAGES:.spec.containers[*].image
POD                                          CONTAINERS                 IMAGES
etcd-k8s-node1                               etcd                       index.docker.io/rancher/hardened-etcd:v3.6.7-k3s1-build20260126
helm-install-rke2-canal-9d26c                helm                       rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-coredns-9jtnr              helm                       rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-metrics-server-7tht2       helm                       rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-runtimeclasses-9hgn5       helm                       rancher/klipper-helm:v0.9.14-build20260210
kube-apiserver-k8s-node1                     kube-apiserver             index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-controller-manager-k8s-node1            kube-controller-manager    index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node1                         kube-proxy                 index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node2                         kube-proxy                 index.docker.io/rancher/hardened-kubernetes:v1.33.7-rke2r3-build20260127
kube-scheduler-k8s-node1                     kube-scheduler             index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
rke2-canal-7cfjk                             calico-node,kube-flannel   rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-canal-w4ltc                             calico-node,kube-flannel   rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-coredns-rke2-coredns-77f54456d4-s8jrv   coredns                    rancher/hardened-coredns:v1.14.1-build20260206
rke2-metrics-server-69f4f95bf7-7nx6h         metrics-server             rancher/hardened-k8s-metrics-server:v0.8.1-build20260206

# 공식 문서에 따른 재시작
systemctl restart rke2-server

# 버전 확인
kubectl get node -owide
NAME        STATUS   ROLES                       AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
k8s-node1   Ready    control-plane,etcd,master   16h   v1.34.4+rke2r1   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
k8s-node2   Ready    <none>                      15h   v1.33.7+rke2r3   192.168.10.12   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1

# 이어서 워커노드 버전 업그레이드 진행 
# k8s-node2
rke2 --version
rke2 version v1.33.7+rke2r3 (7e4fd1a82edf497cab91c220144619bbad659cf4)

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent INSTALL_RKE2_CHANNEL=v1.34 sh -

rke2 --version
rke2 version v1.34.4+rke2r1 (c6b97dc03cefec17e8454a6f45b29f4e3d0a81d6)

dnf repolist
rancher-rke2-1.34-stable                                            Rancher RKE2 1.34 (v1.34)
rancher-rke2-common-stable                                          Rancher RKE2 Common (v1.34)

systemctl restart rke2-agent

# k8s-node1
# kubeconfig 차이가 없는 것 확인
diff /etc/rancher/rke2/rke2.yaml ~/.kube/config
13a14
> preferences: {}

# 노드 조회
kubectl get node -owide
NAME        STATUS   ROLES                       AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
k8s-node1   Ready    control-plane,etcd,master   16h   v1.34.4+rke2r1   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
k8s-node2   Ready    <none>                      15h   v1.34.4+rke2r1   192.168.10.12   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1

kubectl get pod -n kube-system --sort-by=.metadata.creationTimestamp | tac
kube-proxy-k8s-node2                         1/1     Running     0          50s
kube-proxy-k8s-node1                         1/1     Running     0          3m3s
rke2-canal-7cfjk                             2/2     Running     0          5m33s
rke2-canal-w4ltc                             2/2     Running     0          5m58s
rke2-metrics-server-69f4f95bf7-7nx6h         1/1     Running     0          5m59s
rke2-coredns-rke2-coredns-77f54456d4-s8jrv   1/1     Running     0          5m59s
helm-install-rke2-canal-9d26c                0/1     Completed   0          6m7s
helm-install-rke2-coredns-9jtnr              0/1     Completed   0          6m7s
helm-install-rke2-metrics-server-7tht2       0/1     Completed   0          6m7s
helm-install-rke2-runtimeclasses-9hgn5       0/1     Completed   0          6m7s
kube-scheduler-k8s-node1                     1/1     Running     0          6m26s
kube-controller-manager-k8s-node1            1/1     Running     0          6m27s
etcd-k8s-node1                               1/1     Running     0          7m7s
kube-apiserver-k8s-node1                     1/1     Running     0          7m7s
NAME                                         READY   STATUS      RESTARTS   AGE

kubectl get pods -n kube-system -o custom-columns="POD_NAME:.metadata.name,IMAGES:.spec.containers[*].image"
POD_NAME                                     IMAGES
etcd-k8s-node1                               index.docker.io/rancher/hardened-etcd:v3.6.7-k3s1-build20260126
helm-install-rke2-canal-9d26c                rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-coredns-9jtnr              rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-metrics-server-7tht2       rancher/klipper-helm:v0.9.14-build20260210
helm-install-rke2-runtimeclasses-9hgn5       rancher/klipper-helm:v0.9.14-build20260210
kube-apiserver-k8s-node1                     index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-controller-manager-k8s-node1            index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node1                         index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-proxy-k8s-node2                         index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
kube-scheduler-k8s-node1                     index.docker.io/rancher/hardened-kubernetes:v1.34.4-rke2r1-build20260210
rke2-canal-7cfjk                             rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-canal-w4ltc                             rancher/hardened-calico:v3.31.3-build20260206,rancher/hardened-flannel:v0.28.1-build20260206
rke2-coredns-rke2-coredns-77f54456d4-s8jrv   rancher/hardened-coredns:v1.14.1-build20260206
rke2-metrics-server-69f4f95bf7-7nx6h         rancher/hardened-k8s-metrics-server:v0.8.1-build20260206
```

### k8s 버전 자동 업그레이드[^2]
```sh
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/crd.yaml -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
customresourcedefinition.apiextensions.k8s.io/plans.upgrade.cattle.io created
namespace/system-upgrade created
serviceaccount/system-upgrade created
role.rbac.authorization.k8s.io/system-upgrade-controller created
clusterrole.rbac.authorization.k8s.io/system-upgrade-controller created
clusterrole.rbac.authorization.k8s.io/system-upgrade-controller-drainer created
rolebinding.rbac.authorization.k8s.io/system-upgrade created
clusterrolebinding.rbac.authorization.k8s.io/system-upgrade created
clusterrolebinding.rbac.authorization.k8s.io/system-upgrade-drainer created
configmap/default-controller-env created
deployment.apps/system-upgrade-controller created

# 업그레이드 컨트롤러 파드 확인
kubectl get deploy,pod,cm -n system-upgrade
NAME                                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/system-upgrade-controller   1/1     1            1           10s
NAME                                             READY   STATUS    RESTARTS   AGE
pod/system-upgrade-controller-6f9f9b8cf4-rh8kj   1/1     Running   0          10s
NAME                               DATA   AGE
configmap/default-controller-env   10     10s
configmap/kube-root-ca.crt         1      10s

# crd 확인
kubectl get crd | grep upgrade
plans.upgrade.cattle.io                                 2026-02-18T04:23:56Z

kubectl logs -n system-upgrade -l app.kubernetes.io/name=system-upgrade-controller -f

# 업그레이드 계획 생성
cat << EOF | kubectl apply -f -
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: server-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/control-plane
      operator: In
      values:
      - "true"
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/rke2-upgrade
  channel: https://update.rke2.io/v1-release/channels/latest
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: agent-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/control-plane
      operator: DoesNotExist
  prepare:
    args:
    - prepare
    - server-plan
    image: rancher/rke2-upgrade
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/rke2-upgrade
  channel: https://update.rke2.io/v1-release/channels/latest
EOF

# 노드 상태 확인
kubectl get node -owide
NAME        STATUS   ROLES                       AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
k8s-node1   Ready    control-plane,etcd,master   16h   v1.34.4+rke2r1   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
k8s-node2   Ready    <none>                      15h   v1.34.4+rke2r1   192.168.10.12   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1

# 서버부터 작업이 완료된다.
kubectl -n system-upgrade get plans -o wide
NAME          IMAGE                  CHANNEL                                             VERSION   COMPLETE   MESSAGE   APPLYING
agent-plan    rancher/rke2-upgrade   https://update.rke2.io/v1-release/channels/latest             False                ["k8s-node2"]
server-plan   rancher/rke2-upgrade   https://update.rke2.io/v1-release/channels/latest             True                ["k8s-node1"]

kubectl -n system-upgrade get jobs
NAME                                                              STATUS    COMPLETIONS   DURATION   AGE
apply-agent-plan-on-k8s-node2-with-58646b4639f2f26db71730-e1707   Running   0/1           24s        24s
apply-server-plan-on-k8s-node1-with-58646b4639f2f26db7173-f5d08   Complete   1/1           53s        92s

kubectl get pod -n system-upgrade -owide
NAME                                                              READY   STATUS      RESTARTS   AGE     IP              NODE        NOMINATED NODE   READINESS GATES
apply-agent-plan-on-k8s-node2-with-58646b4639f2f26db71730-w6t44   0/1     Unknown     0          107s    192.168.10.12   k8s-node2   <none>           <none>
apply-server-plan-on-k8s-node1-with-58646b4639f2f26db7173-5vkrd   0/1     Unknown     0          107s    192.168.10.11   k8s-node1   <none>           <none>
apply-server-plan-on-k8s-node1-with-58646b4639f2f26db7173-7sjk7   0/1     Completed   0          62s     192.168.10.11   k8s-node1   <none>           <none>
system-upgrade-controller-6f9f9b8cf4-rh8kj                        1/1     Running     0          2m29s   10.42.0.7       k8s-node1   <none>           <none>

# 업그레이드 플랜이 호스트의 루트 디렉토리를 볼 수 있도록 볼륨이 마운트되어 있는지 확인
kubectl describe pod -n system-upgrade |grep ^Volumes: -A4
Volumes:
  host-root:
    Type:          HostPath (bare host directory volume)
    Path:          /
    HostPathType:  Directory
--
Volumes:
  host-root:
    Type:          HostPath (bare host directory volume)
    Path:          /
    HostPathType:  Directory
--
Volumes:
  host-root:
    Type:          HostPath (bare host directory volume)
    Path:          /
    HostPathType:  Directory
--
Volumes:
  host-root:
    Type:          HostPath (bare host directory volume)
    Path:          /
    HostPathType:  Directory
--
Volumes:
  etc-ssl:
    Type:          HostPath (bare host directory volume)
    Path:          /etc/ssl
    HostPathType:  DirectoryOrCreate

# 로그 확인
kubectl logs -n system-upgrade -l app.kubernetes.io/name=system-upgrade-controller
I0218 04:26:41.551354       1 event.go:389] "Event occurred" object="system-upgrade/agent-plan" fieldPath="" kind="Plan" apiVersion="upgrade.cattle.io/v1" type="Normal" reason="JobComplete" message="Job completed on Node k8s-node2"
I0218 04:26:41.564451       1 event.go:389] "Event occurred" object="system-upgrade/agent-plan" fieldPath="" kind="Plan" apiVersion="upgrade.cattle.io/v1" type="Normal" reason="Complete" message="Jobs complete for version v1.35.1-rke2r1. Hash: 58646b4639f2f26db717305a88bd392986d5f96e4cd53d78dc1852d9"

# 버전 업그레이드 완료 확인
k get nodes -o wide
NAME        STATUS   ROLES                       AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
k8s-node1   Ready    control-plane,etcd,master   16h   v1.35.1+rke2r1   192.168.10.11   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
k8s-node2   Ready    <none>                      15h   v1.35.1+rke2r1   192.168.10.12   <none>        Rocky Linux 9.6 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.1.5-k3s1
```


[^1]: https://docs.rke2.io/
[^2]: https://docs.rke2.io/upgrades/automated
[^3]: https://update.rke2.io/v1-release/channels 