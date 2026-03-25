#!/usr/bin/env bash

echo ">>>> Initial Config Start <<<<"

echo "[TASK 1] Setting Profile & Change Timezone"
echo 'alias vi=vim' >> /etc/profile
echo "sudo su -" >> /home/vagrant/.bashrc
ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime


echo "[TASK 2] Disable AppArmor"
systemctl stop firewalld && systemctl disable firewalld >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1


echo "[TASK 3] Disable and turn off SWAP"
swapoff -a && sed -i '/swap/s/^/#/' /etc/fstab


echo "[TASK 4] Install Packages"
dnf update -q >/dev/null 2>&1
dnf install epel-release curl ca-certificates gnupg2 dnf-plugin-versionlock dnf-plugins-core git -y -q >/dev/null 2>&1
# Download the public signing key for the Kubernetes package repositories.  
K8SMMV=$(echo $1 | sed -En 's/^([0-9]+\.[0-9]+)\..*/\1/p')

# Add k8s repo
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf config-manager --add-repo https://kubecolor.github.io/packages/rpm/kubecolor.repo

# packets traversing the bridge are processed by iptables for filtering
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf

# enable br_netfilter for iptables 
modprobe br_netfilter
modprobe overlay
echo "br_netfilter" >> /etc/modules-load.d/k8s.conf
echo "overlay" >> /etc/modules-load.d/k8s.conf

echo "[TASK 5] Install Kubernetes components (kubeadm, kubelet and kubectl)"
# Update the apt package index, install kubelet, kubeadm and kubectl, and pin their version
dnf update >/dev/null 2>&1

# apt list -a kubelet ; apt list -a containerd.
dnf install -y kubelet-$1 kubectl-$1 kubeadm-$1 containerd.io-$2 --disableexcludes=kubernetes
# dnf versionlock add kubelet kubeadm kubectl >/dev/null 2>&1

# containerd configure to default and cgroup managed by systemd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# avoid WARN&ERRO(default endpoints) when crictl run  
cat <<EOF > /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# ready to install for k8s 
systemctl restart containerd && systemctl enable containerd
systemctl enable --now kubelet

echo "[TASK 6] Install Packages & Helm"
dnf install -y bridge-utils sshpass net-tools conntrack ngrep tcpdump ipset iputils wireguard-tools jq tree bash-completion unzip kubecolor
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo ">>>> Initial Config End <<<<"