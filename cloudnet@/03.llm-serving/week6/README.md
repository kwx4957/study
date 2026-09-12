## LLM Serving 스터디 6주차

> GCP GPU VM Rocky Linux 9 기반 NVIDIA GPU를 구성하고 저수준으로 gpu를 파악하고 컨테이너에서 k3s 이르기까지 vllm 기반 LLM 서빙을 실습한 내용입니다.

### 목차 

- [1. VM 생성을 위한 GCP VM 설정](#VM-생성을-위한-GCP-설정)
- [2. VM GPU 설정](#vm-gpu-설정)
- [3. GPU Docekr](#GPU-Docekr)
- [4. k3s 설치](#k3s-설치)
- [5. kube-promethues-stack 설치](#kube-promethues-stack)
- [6. DCGM Exporter 설치](#DCGM-Exporter)
- [7. Nvdia GPU Operator](#Nvdia-GPU-Operator)
- [8. vllm 배포](#vllm-배포)


### VM 생성을 위한 GCP 설정

우선 gcp에서 순수한 VM을 생성하기 위해서 gcloud를 설치한다.   
스펙은 GPU는 `T4`와 OS `Rocky 9`, 디스크 용량은 `100GB`, MACHINE_TYPE은 `n1-standard-8`, zons은 `asia-northeast3-c` 이다

하지만 gcp에서 vm 생성할 시 gpu 자원이 모자라서 쉽게 생성되지 않는다. 이 경우 모든 zones를 디스커버리하여 t4타입의 vm 을 생성할수 잇도록 했다.

```sh
# gcp 패키지 레포짙리 추가
sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

sudo dnf install libxcrypt-compat.x86_64

sudo dnf install google-cloud-cli

# gcloud 초기작업
gcloud init --console-only

# 프로젝트 생성
gcloud projects create tmp-20260911   --name="tmp-test"

gcloud auth list

gcloud config list

gcloud projects list

# 기본 프로젝트 설정
gcloud config set project tmp-20260911

# VM 생성 명렁어 
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=asia-northeast3-c
export VM_NAME=hami-workshop
export MACHINE_TYPE=n1-standard-8
export GPU_TYPE=nvidia-tesla-t4
export IMAGE_FAMILY=rocky-linux-9-optimized-gcp
export IMAGE_PROJECT=rocky-linux-cloud
export DISK_SIZE=100

gcloud compute instances create ${VM_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --machine-type=${MACHINE_TYPE} \
    --accelerator=type=${GPU_TYPE},count=1 \
    --maintenance-policy=TERMINATE \
    --image-family=${IMAGE_FAMILY} \
    --image-project=${IMAGE_PROJECT} \
    --boot-disk-size=${DISK_SIZE}GB \
    --boot-disk-type=pd-ssd

# 앞선 zone에서 VM 생성이 L4 gpu가 안잡히는 경우, 모든 zone에 대해서 탐색하여 vm 생성을 시도한다.
ZONES=$(gcloud compute accelerator-types list \
  --project="$PROJECT_ID" \
  --filter='name="nvidia-tesla-t4"' \
  --format='value(zone)')

for MACHINE_TYPE in n1-standard-8; do
  for ZONE in $ZONES; do
    echo "Trying: $ZONE / $MACHINE_TYPE"

    gcloud compute instances create "$VM_NAME" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --accelerator="type=$GPU_TYPE,count=1" \
      --image-family="$IMAGE_FAMILY" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size="${DISK_SIZE}GB" \
      --boot-disk-type=pd-balanced \
      --maintenance-policy=TERMINATE && exit 0

    echo "Failed: $ZONE / $MACHINE_TYPE"
  done
done

echo "All attempts failed."

# VM 방화벽 개방
# VM의 공인 ip로 그라파나, minio, vllm에 대해서 호출이 가능하다.
export NETWORK=default
export MY_IP=$(curl -4 -s ifconfig.me)

gcloud compute firewall-rules create allow-workshop-my-ip \
--project="$PROJECT_ID" \
--network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22,tcp:30001,tcp:30002,tcp:30003,tcp:30004,tcp:30005 \
  --source-ranges="${MY_IP}/32"

# vm 생성 직후 ssh 접속
gcloud compute ssh kwx4957@hami-workshop \
  --project=tmp-20260911 \
  --zone=europe-central2-b

# ip 확인
ip -c -br addr
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             10.186.0.2/32 fe80::fe98:e607:d310:8683/64

# vm 방화벽 비활성화, 테스트 용도
sudo systemctl stop firewalld

# 모든 작업이 끝난 직후, vm 및 디스크를 삭제한다.
# vm 삭제
gcloud compute instances list \
  --project=tmp-20260911

gcloud compute instances delete <VM_NAME> \
  --project=tmp-20260911 \
  --zone=asia-northeast3-a

# 디스크 삭제 
gcloud compute disks list \
  --project=tmp-20260911

gcloud compute disks delete <DISK_NAME> \
  --project=tmp-20260911 \
  --zone=asia-northeast3-a
```


### VM GPU 설정

pciutils, EPEL, CRB, kernel headers/devel, NVIDIA CUDA repo를 구성 및 nvidia-open, cuda-drivers를 설치한다  
nvidia-smi, dkms status, lsmod, /dev/nvidia*, libcuda.so 등을 확인해 GPU를 정상적으로 인식하는지 확인한다.  

```sh
# lspci 설치
sudo dnf install -y pciutils

# pci 조회
# GPU 하드웨어 단에서 PCI가 정상 부착되어있는지 확인
lspci | grep -i nvidia
00:04.0 3D controller: NVIDIA Corporation TU104GL [Tesla T4] (rev a1)

# GPU 관련 패키지 설치
sudo dnf install epel-release -y
sudo dnf config-manager --enable crb
sudo dnf groupinstall "Development Tools" -y
sudo dnf install kernel-devel-matched kernel-headers -y
sudo dnf config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/rhel9/$(uname -m)/cuda-rhel9.repo
sudo dnf clean expire-cache
sudo dnf install nvidia-open -y
sudo dnf install cuda-drivers -y

reboot

# 패키지 설치 조회
rpm -qa | grep -iE 'nvidia|cuda|dkms|kernel-devel|kernel-headers'
kernel-headers-5.14.0-687.42.1+2.1.el9_8_ciq.x86_64
kernel-devel-5.14.0-687.42.1+2.1.el9_8_ciq.x86_64
kernel-devel-matched-5.14.0-687.42.1+2.1.el9_8_ciq.x86_64
nvidia-driver-common-615.71.09-1.el9.x86_64
nvidia-driver-cuda-libs-615.71.09-1.el9.x86_64
nvidia-libXNVCtrl-615.71.09-1.el9.x86_64
libnvidia-fbc-615.71.09-1.el9.x86_64
nvidia-persistenced-615.71.09-1.el9.x86_64
dkms-3.4.3-2.el9.noarch
nvidia-modprobe-615.71.09-1.el9.x86_64
nvidia-driver-selinux-0.1-2.el9.noarch
nvidia-kmod-common-615.71.09-1.el9.noarch
kmod-nvidia-open-dkms-615.71.09-1.el9.noarch
nvidia-driver-cuda-615.71.09-1.el9.x86_64
nvidia-driver-libs-615.71.09-1.el9.x86_64
nvidia-driver-615.71.09-1.el9.x86_64
nvidia-settings-615.71.09-1.el9.x86_64
nvidia-open-615.71.09-1.el9.noarch

# 설치가 안되어잇음
dkms status
nvidia/615.71.09: added

# NVIDIA 모듈 빌드 및 설치
sudo dkms autoinstall

# 모듈 의존성 갱신
sudo depmod -a

# nvidia 커널 모듈 로드 
sudo modprobe nvidia

# 현재 커널 모듈 상태 조회
dkms status
nvidia/615.71.09, 5.14.0-687.42.1+2.1.el9_8_ciq.x86_64, x86_64: installed

# gpu 정보 출력 
nvidia-smi
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 615.71.09              KMD Version: 615.71.09     CUDA UMD Version: 13.4     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  Tesla T4                       Off |   00000000:00:04.0 Off |                    0 |
| N/A   61C    P8             10W /   70W |       0MiB /  15360MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+

# 커널 버전 조회
uname -a
Linux hami-workshop 5.14.0-687.42.1+2.1.el9_8_ciq.x86_64 #1 SMP PREEMPT_DYNAMIC Thu Sep 3 14:13:50 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux

# 커널에서 nvidia 커널 모듈 탐색
find /lib/modules/$(uname -r) -name '*nvidia*'
/lib/modules/5.14.0-687.42.1+2.1.el9_8_ciq.x86_64/extra/nvidia.ko.xz
/lib/modules/5.14.0-687.42.1+2.1.el9_8_ciq.x86_64/extra/nvidia-modeset.ko.xz
/lib/modules/5.14.0-687.42.1+2.1.el9_8_ciq.x86_64/extra/nvidia-drm.ko.xz
/lib/modules/5.14.0-687.42.1+2.1.el9_8_ciq.x86_64/extra/nvidia-uvm.ko.xz
/lib/modules/5.14.0-687.42.1+2.1.el9_8_ciq.x86_64/extra/nvidia-peermem.ko.xz

# 커널 모듈 로드 여부 조회
lsmod | grep nvidia
nvidia_uvm           2473984  0
nvidia_drm            163840  0
drm_display_helper    344064  1 nvidia_drm
nvidia_modeset       1556480  1 nvidia_drm
nvidia              16891904  2 nvidia_uvm,nvidia_modeset
video                  77824  1 nvidia_modeset
drm_ttm_helper         16384  1 nvidia_drm
drm_client_lib         16384  1 nvidia_drm
drm_kms_helper        278528  4 drm_display_helper,drm_ttm_helper,nvidia_drm,drm_client_lib
drm                   864256  8 drm_kms_helper,drm_display_helper,nvidia,drm_ttm_helper,nvidia_drm,drm_client_lib,ttm

# 커널 드라이버가 gpu 디바이스 생성 상태 
ls -l /dev/nvidia0
crw-rw-rw-. 1 root root 195, 0 Sep 11 05:05 /dev/nvidia0

ls -l /dev/nvidia*
crw-rw-rw-. 1 root root 195,   0 Sep 11 05:05 /dev/nvidia0
crw-rw-rw-. 1 root root 195, 255 Sep 11 05:05 /dev/nvidiactl
crw-rw-rw-. 1 root root 234,   0 Sep 11 05:05 /dev/nvidia-uvm
crw-rw-rw-. 1 root root 234,   1 Sep 11 05:05 /dev/nvidia-uvm-tools

/dev/nvidia-caps:
total 0
cr--------. 1 root root 238, 1 Sep 11 05:05 nvidia-cap1
cr--r--r--. 1 root root 238, 2 Sep 11 05:05 nvidia-cap2

sudo find /usr -name 'libcuda*' 2>/dev/null

# CUDA Driver API의 사용자 공간 라이브러리
ls -l /usr/lib64/libcuda*
lrwxrwxrwx. 1 root root        28 Sep  5 03:46 /usr/lib64/libcudadebugger.so.1 -> libcudadebugger.so.615.71.09
-rwxr-xr-x. 1 root root  12198904 Sep  4 21:25 /usr/lib64/libcudadebugger.so.615.71.09
lrwxrwxrwx. 1 root root        20 Sep  5 03:46 /usr/lib64/libcuda.so -> libcuda.so.615.71.09
lrwxrwxrwx. 1 root root        20 Sep  5 03:46 /usr/lib64/libcuda.so.1 -> libcuda.so.615.71.09
-rwxr-xr-x. 1 root root 112475080 Sep  4 22:54 /usr/lib64/libcuda.so.615.71.09

# NVIDIA가 제공하는 사용자 공간 라이브러리
ls -l /usr/lib64/libnvidia*
lrwxrwxrwx. 1 root root        32 Sep  5 03:46 /usr/lib64/libnvidia-allocator.so.1 -> libnvidia-allocator.so.615.71.09
-rwxr-xr-x. 1 root root    152904 Sep  4 22:08 /usr/lib64/libnvidia-allocator.so.615.71.09
....

# 부팅 과정에서 정상적으로 gpu pci를 로드한 것을 알수가 있다. 
dmesg | grep -i nvidia
[    1.532722] Loaded X.509 cert 'Rocky Enterprise Software Foundation: Nvidia GPU OOT Signing 101: 816ba9c770e6960cefe378020865d4ebbc352a7d'
[ 1054.193377] nvidia: loading out-of-tree module taints kernel.
[ 1054.193435] nvidia: module verification failed: signature and/or required key missing - tainting kernel
[ 1054.315597] nvidia-nvlink: Nvlink Core is being initialized, major device number 237
[ 1054.335126] NVRM: Failed to read PCI extended capability header at offset 0x100 while searching for NVIDIA DVSEC3, rc 0xffffffea
[ 1055.734346] NVRM: loading NVIDIA UNIX Open Kernel Module for x86_64  615.71.09  Release Build  (root@hami-workshop)  Fri Sep 11 05:01:56 AM UTC 2026
[ 1055.832100] Modules linked in: nvidia_modeset(OE+) nvidia(OE) video wmi drm_ttm_helper ttm drm_client_lib drm_kms_helper nft_fib_inet nft_fib_ipv4 nft_fib_ipv6 nft_fib nft_reject_inet nf_reject_ipv4 nf_reject_ipv6 nft_reject nft_ct nft_chain_nat nf_nat nf_conntrack nf_defrag_ipv6 nf_defrag_ipv4 nf_tables nfnetlink vfat fat intel_rapl_msr intel_rapl_common rapl pvpanic_mmio i2c_piix4 pcspkr virtio_balloon pvpanic i2c_smbus fuse drm xfs libcrc32c crct10dif_pclmul crc32_pclmul crc32c_intel virtio_net net_failover ghash_clmulni_intel failover serio_raw sd_mod sg virtio_scsi nvme nvme_core nvme_keyring nvme_auth i2c_dev
[ 1056.059333]  ? nvkms_alloc+0x8b/0xb0 [nvidia_modeset]
[ 1056.065925]  ? nvkms_alloc+0x8b/0xb0 [nvidia_modeset]
[ 1056.072516]  nv_vasprintf+0x2b/0xd0 [nvidia_modeset]
[ 1056.089637]  ? nvVEvoLog+0x32/0xa0 [nvidia_modeset]
[ 1056.096027]  ? __pfx_nvkms_init+0x10/0x10 [nvidia_modeset]
[ 1056.103050]  ? nvEvoLog+0x4a/0x60 [nvidia_modeset]
[ 1056.119953]  ? nvKmsModuleLoad+0x24/0x200 [nvidia_modeset]
[ 1056.131497]  ? __pfx_nvkms_init+0x10/0x10 [nvidia_modeset]
[ 1056.138531]  ? nvkms_init+0x1a3/0xff0 [nvidia_modeset]
[ 1056.287381] nvidia-modeset: Loading NVIDIA UNIX Open Kernel Mode Setting Driver for x86_64  615.71.09  Release Build  (root@hami-workshop)  Fri Sep 11 05:00:13 AM UTC 2026
[ 1056.347366] [drm] [nvidia-drm] [GPU ID 0x00000004] Loading driver
[ 1056.354513] [drm] Initialized nvidia-drm 0.0.0 for 0000:00:04.0 on minor 0
[ 1056.354643] nvidia 0000:00:04.0: [drm] No compatible format found
[ 1056.354654] nvidia 0000:00:04.0: [drm] Cannot find any crtc or sizes
```

TS
```sh
# 패키지 설치 후 리부트 후에도 인식을 못한다. 
nvidia-smi 

# 패키지는 설치되어있다. 
rpm -qa | grep -iE 'nvidia|cuda|dkms|kernel-devel|kernel-headers'

# 설치가 안되어잇음
dkms status
nvidia/615.71.09: added

# 자동 설치
sudo dkms autoinstall

# 모듈 의존성 갱신
sudo depmod -a

sudo modprobe nvidia

dkms status
```


### GPU Docekr 

Docker 설치 이후 `nvidia-container-toolkit`을 추가한다  
nvidia-ctk runtime configure --runtime=docker로 Docker 런타임을 NVIDIA GPU 사용 가능 상태로 만들고, 컨테이너 내부에서 GPU가 보이는지 확인한다.

```sh
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl --now enable docker

docker run --rm hello-world
Hello from Docker!
This message shows that your installation appears to be working correctly.

sudo dnf install -y curl tree

curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.20.0-1
sudo dnf install -y \
    nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}

nvidia-container-cli --version
cli-version: 1.20.0
lib-version: 1.20.0
build date: 2026-08-12T15:52+0000
build revision: 3e428194f8616a81e16834d27365e4a663668533
build compiler: gcc 4.8.5 20150623 (Red Hat 4.8.5-44)
build platform: x86_64
build flags: -D_GNU_SOURCE -D_FORTIFY_SOURCE=2 -DNDEBUG -std=gnu11 -O2 -g -fdata-sections -ffunction-sections -fplan9-extensions -fstack-protector -fno-strict-aliasing -fvisibility=hidden -Wall -Wextra -Wcast-align -Wpointer-arith -Wmissing-prototypes -Wnonnull -Wwrite-strings -Wlogical-op -Wformat=2 -Wmissing-format-attribute -Winit-self -Wshadow -Wstrict-prototypes -Wunreachable-code -Wconversion -Wsign-conversion -Wno-unknown-warning-option -Wno-format-extra-args -Wno-gnu-alignof-expression -Wl,-zrelro -Wl,-znow -Wl,-zdefs -Wl,--gc-sections

nvidia-ctk --version
NVIDIA Container Toolkit CLI version 1.20.0
commit: 5505e2f94d9aaa08561490db974ba3cd676af20

# docker가 nvidia gpu를 사용할수 있도록 런타임을 자동 구성해준다. 
sudo nvidia-ctk runtime configure --runtime=docker
INFO[0000] Config file does not exist; using empty config
INFO[0000] Wrote updated config to /etc/docker/daemon.json
INFO[0000] It is recommended that docker daemon be restarted.

sudo systemctl restart docker

# 도커 내에서 NVIDIA GPU가 정상적으로 사용 가능한지 테스트한다.
# --gpus all은 호스트의 모든 gpu를 컨테이너에 전달한다는 의미이다.
docker run --rm --gpus all ubuntu nvidia-smi
Fri Sep 11 05:17:32 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 615.71.09              KMD Version: 615.71.09     CUDA UMD Version: 13.4     |
|   0  Tesla T4                       Off |   00000000:00:04.0 Off |                    0 |


# 컨테이너에서 NVIDIA 라이브러리를 자동으로 불러온다
cat /etc/nvidia-container-runtime/config.toml
#accept-nvidia-visible-devices-as-volume-mounts = false
#accept-nvidia-visible-devices-envvar-when-unprivileged = true
disable-require = false
supported-driver-capabilities = "compat32,compute,display,graphics,ngx,utility,video"
#swarm-resource = "DOCKER_RESOURCE_GPU"


[nvidia-container-cli]
#debug = "/var/log/nvidia-container-toolkit.log"
environment = []
#ldcache = "/etc/ld.so.cache"
ldconfig = "@/sbin/ldconfig"
load-kmods = true
#no-cgroups = false
#path = "/usr/bin/nvidia-container-cli"
#root = "/run/nvidia/driver"
#user = "root:video"

[nvidia-container-runtime]
#debug = "/var/log/nvidia-container-runtime.log"
log-level = "info"
mode = "auto"
runtimes = ["runc", "crun"]

[nvidia-container-runtime.modes]

[nvidia-container-runtime.modes.cdi]
annotation-prefixes = ["cdi.k8s.io/"]
default-kind = "nvidia.com/gpu"
spec-dirs = ["/etc/cdi", "/var/run/cdi"]

[nvidia-container-runtime.modes.csv]
mount-spec-path = "/etc/nvidia-container-runtime/host-files-for-container.d"

[nvidia-container-runtime.modes.legacy]
cuda-compat-mode = "ldconfig"

[nvidia-container-runtime-hook]
path = "nvidia-container-runtime-hook"
skip-mode-detection = false

[nvidia-ctk]


# 해당 설정으로 통해 컨테이너가 GPU를 사용할수 있따.
# GPU 디바이스, NVIDIA 라이브러리, 환경변수, hook, 호스트 마운트을 컨테이너에 자동 주입한다. 
cat /var/run/cdi/nvidia.yaml
---
cdiVersion: 0.7.0
kind: nvidia.com/gpu
devices:
    - name: "0"
      containerEdits:
        deviceNodes:
            - path: /dev/nvidia0
              major: 195
              fileMode: 438
              permissions: rwm
            - path: /dev/dri/card0
              major: 226
              fileMode: 432
              permissions: rwm
              gid: 39
            - path: /dev/dri/renderD128
              major: 226
              minor: 128
              fileMode: 438
              permissions: rwm
              gid: 105
        hooks:
            - hookName: createContainer
              path: /usr/bin/nvidia-cdi-hook
              args:
                - nvidia-cdi-hook
                - create-symlinks
                - --link
                - ../card0::/dev/dri/by-path/pci-0000:00:04.0-card
                - --link
                - ../renderD128::/dev/dri/by-path/pci-0000:00:04.0-render
              env:
                - NVIDIA_CTK_DEBUG=false
        additionalGids:
            - 39
    - name: GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256
      containerEdits:
        deviceNodes:
            - path: /dev/nvidia0
              major: 195
              fileMode: 438
              permissions: rwm
            - path: /dev/dri/card0
              major: 226
              fileMode: 432
              permissions: rwm
              gid: 39
            - path: /dev/dri/renderD128
              major: 226
              minor: 128
              fileMode: 438
              permissions: rwm
              gid: 105
        hooks:
            - hookName: createContainer
              path: /usr/bin/nvidia-cdi-hook
              args:
                - nvidia-cdi-hook
                - create-symlinks
                - --link
                - ../card0::/dev/dri/by-path/pci-0000:00:04.0-card
                - --link
                - ../renderD128::/dev/dri/by-path/pci-0000:00:04.0-render
              env:
                - NVIDIA_CTK_DEBUG=false
        additionalGids:
            - 39
    - name: all
      containerEdits:
        deviceNodes:
            - path: /dev/nvidia0
              major: 195
              fileMode: 438
              permissions: rwm
            - path: /dev/dri/card0
              major: 226
              fileMode: 432
              permissions: rwm
              gid: 39
            - path: /dev/dri/renderD128
              major: 226
              minor: 128
              fileMode: 438
              permissions: rwm
              gid: 105
        hooks:
            - hookName: createContainer
              path: /usr/bin/nvidia-cdi-hook
              args:
                - nvidia-cdi-hook
                - create-symlinks
                - --link
                - ../card0::/dev/dri/by-path/pci-0000:00:04.0-card
                - --link
                - ../renderD128::/dev/dri/by-path/pci-0000:00:04.0-render
              env:
                - NVIDIA_CTK_DEBUG=false
        additionalGids:
            - 39
containerEdits:
    env:
        - NVIDIA_CTK_LIBCUDA_DIR=/usr/lib64
        - NVIDIA_VISIBLE_DEVICES=void
    deviceNodes:
        - path: /dev/nvidia-uvm
          major: 234
          fileMode: 438
          permissions: rwm
        - path: /dev/nvidia-uvm-tools
          major: 234
          minor: 1
          fileMode: 438
          permissions: rwm
        - path: /dev/nvidiactl
          major: 195
          minor: 255
          fileMode: 438
          permissions: rwm
    hooks:
        - hookName: createContainer
          path: /usr/bin/nvidia-cdi-hook
          args:
            - nvidia-cdi-hook
            - create-symlinks
            - --link
            - ../libnvidia-allocator.so.1::/usr/lib64/gbm/nvidia-drm_gbm.so
          env:
            - NVIDIA_CTK_DEBUG=false
        - hookName: createContainer
          path: /usr/bin/nvidia-cdi-hook
          args:
            - nvidia-cdi-hook
            - create-symlinks
            - --link
            - libEGL_nvidia.so.615.71.09::/usr/lib64/libEGL_nvidia.so.0
...
          env:
            - NVIDIA_CTK_DEBUG=false
        - hookName: createContainer
          path: /usr/bin/nvidia-cdi-hook
          args:
            - nvidia-cdi-hook
            - enable-cuda-compat
            - --host-driver-version=615.71.09
          env:
            - NVIDIA_CTK_DEBUG=false
....
# 컨테이너에 호스트의 GPU 정보를 마운트 하는 역할을 수행한다. 이덕에 별도의 마운트 작업없이도 자동으로 컨테이너가 gpu를 인식한다.
    mounts:
        - hostPath: /usr/bin/nvidia-cuda-mps-control
          containerPath: /usr/bin/nvidia-cuda-mps-control
          options:
            - ro
            - nosuid
            - nodev
            - rbind
            - rprivate
        - hostPath: /usr/bin/nvidia-smi
          containerPath: /usr/bin/nvidia-smi
          options:
            - ro
            - nosuid
            - nodev
            - rbind
            - rprivate
...


# NVIDIA GPU의 드라이버 상태를 유지하는 백그라운드 데몬
ls -l /run/nvidia-persistenced/socket
srwxrwxrwx. 1 nvidia-persistenced nvidia-persistenced 0 Sep 11 05:21 /run/nvidia-persistenced/socket

docker run --rm -it --gpus all ubuntu bash

nvidia-smi
Fri Sep 11 05:22:38 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 615.71.09              KMD Version: 615.71.09     CUDA UMD Version: 13.4     |
|   0  Tesla T4                       Off |   00000000:00:04.0 Off |                    0 |

which nvidia-smi
/usr/bin/nvidia-smi

df -hT
Filesystem     Type     Size  Used Avail Use% Mounted on
overlay        overlay  100G  7.3G   93G   8% /
tmpfs          tmpfs     64M     0   64M   0% /dev
shm            tmpfs     64M     0   64M   0% /dev/shm
/dev/sda2      xfs      100G  7.3G   93G   8% /usr/bin/nvidia-smi
tmpfs          tmpfs    4.0K  4.0K     0 100% /run/nvidia-ctk-hook4daba44c-85a3-44d6-9056-dd941df66934
tmpfs          tmpfs    4.0K     0  4.0K   0% /proc/acpi

ls -l /dev/nvidia*
crw-rw-rw-+    1 root root 234,   0 Sep 11 05:22 /dev/nvidia-uvm
crw-rw-rw-+    1 root root 234,   1 Sep 11 05:22 /dev/nvidia-uvm-tools
crw-rw-rw-+    1 root root 195,   0 Sep 11 05:22 /dev/nvidia0
crw-rw-rw-+    1 root root 195, 255 Sep 11 05:22 /dev/nvidiactl
/dev/nvidia-caps:
total 0
cr--------+1 root root 238, 1 Sep 11 05:22 nvidia-cap1
cr--r--r--+1 root root 238, 2 Sep 11 05:22 nvidia-cap2

ls -l /usr/lib/x86_64-linux-gnu/libcuda*
lrwxrwxrwx+     1 root root        12 Sep 11 05:22 /usr/lib64/libcuda.so -> libcuda.so.1
lrwxrwxrwx+     1 root root        20 Sep 11 05:22 /usr/lib64/libcuda.so.1 -> libcuda.so.615.71.09
-rwxr-xr-x+     1 root root 112475080 Sep  4 22:54 /usr/lib64/libcuda.so.615.71.09
lrwxrwxrwx+     1 root root        28 Sep 11 05:22 /usr/lib64/libcudadebugger.so.1 -> libcudadebugger.so.615.71.09
-rwxr-xr-x+     1 root root  12198904 Sep  4 21:25 /usr/lib64/libcudadebugger.so.615.71.09

ls -l /usr/lib/x86_64-linux-gnu/libnvidia*
lrwxrwxrwx+                                           1 root root        32 Sep 11 05:22 /usr/lib64/libnvidia-allocator.so.1 -> libnvidia-allocator.so.615.71.09
-rwxr-xr-x+                                           1 root root    152904 Sep  4 22:08 /usr/lib64/libnvidia-allocator.so.615.71.09
...

env | grep -i nvidia
NVIDIA_VISIBLE_DEVICES=void
NVIDIA_CTK_LIBCUDA_DIR=/usr/lib64

exit
```

TS 

Chatgpt
/run/nvidia-persistenced/socket은 NVIDIA Container Toolkit이 만드는 파일이 아니라, 아래 서비스가 정상 기동될 때 생성된다.
원인은 서비스가 처음 뜰 때 /dev/nvidia* 디바이스 파일이 아직 없어서 실패했고, 이후 디바이스 파일이 생겼지만 systemd가 “너무 빨리 여러 번 실패했다”고 판단해서 재시작을 막고 있었던 것입니다.

```sh
sudo systemctl status nvidia-persistenced --no-pager -l
× nvidia-persistenced.service - NVIDIA Persistence Daemon
     Loaded: loaded (/usr/lib/systemd/system/nvidia-persistenced.service; enabled; preset: enabled)
     Active: failed (Result: exit-code) since Fri 2026-09-11 04:47:09 UTC; 33min ago
        CPU: 18ms

Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Scheduled restart job, restart counter is at 5.
Sep 11 04:47:09 hami-workshop systemd[1]: Stopped NVIDIA Persistence Daemon.
Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Start request repeated too quickly.
Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Failed with result 'exit-code'.
Sep 11 04:47:09 hami-workshop systemd[1]: Failed to start NVIDIA Persistence Daemon.

sudo journalctl -u nvidia-persistenced -b --no-pager -n 50
ep 11 04:47:05 hami-workshop nvidia-persistenced[887]: Started (887)
Sep 11 04:47:05 hami-workshop nvidia-persistenced[887]: Failed to query NVIDIA devices. Please ensure that the NVIDIA device files (/dev/nvidia*) exist, and that user 991 has read and write permissions for those files.
Sep 11 04:47:05 hami-workshop nvidia-persistenced[887]: Shutdown (887)
Sep 11 04:47:05 hami-workshop nvidia-persistenced[881]: nvidia-persistenced failed to initialize. Check syslog for more details.
Sep 11 04:47:06 hami-workshop systemd[1]: nvidia-persistenced.service: Control process exited, code=exited, status=1/FAILURE
Sep 11 04:47:06 hami-workshop systemd[1]: nvidia-persistenced.service: Failed with result 'exit-code'.
Sep 11 04:47:06 hami-workshop systemd[1]: Failed to start NVIDIA Persistence Daemon.
Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Scheduled restart job, restart counter is at 5.
Sep 11 04:47:09 hami-workshop systemd[1]: Stopped NVIDIA Persistence Daemon.
Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Start request repeated too quickly.
Sep 11 04:47:09 hami-workshop systemd[1]: nvidia-persistenced.service: Failed with result 'exit-code'.


sudo systemctl reset-failed nvidia-persistenced

sudo systemctl restart nvidia-persistenced

sudo systemctl status nvidia-persistenced --no-pager -l
● nvidia-persistenced.service - NVIDIA Persistence Daemon
     Loaded: loaded (/usr/lib/systemd/system/nvidia-persistenced.service; enabled; preset: enabled)
     Active: active (running) since Fri 2026-09-11 05:21:58 UTC; 2s ago
    Process: 31767 ExecStart=/usr/bin/nvidia-persistenced (code=exited, status=0/SUCCESS)
   Main PID: 31768 (nvidia-persiste)
      Tasks: 1 (limit: 93936)
     Memory: 1008.0K (peak: 1.5M)
        CPU: 21ms
     CGroup: /system.slice/nvidia-persistenced.service
             └─31768 /usr/bin/nvidia-persistenced

Sep 11 05:21:58 hami-workshop systemd[1]: Starting NVIDIA Persistence Daemon...
Sep 11 05:21:58 hami-workshop nvidia-persistenced[31768]: Started (31768)
Sep 11 05:21:58 hami-workshop systemd[1]: Started NVIDIA Persistence Daemon.
```


### k3s 설치

간단한 k8s 실습을 위해 k3s를 설치한다. 이후 ontainerd의 NVIDIA runtime 설정, nvidia RuntimeClass를 활성화한다.  

NVIDIA k8s device plugin `v0.20.0`을 배포하고, DaemonSet과 Pod가 정상 Running 상태인지 확인합니다. 

그리고나서 노드 정보를 조회해, 노드가 nvidia.com/gpu allocatable 값이 1로 잡히는지 확인한다.


기존 도커 삭제
```sh
# 1. 상태 사전 확인
docker ps -a
docker images

# 2. 서비스 중지/비활성화
sudo systemctl disable --now docker.service docker.socket containerd.service

# 3. 패키지 제거
sudo dnf remove -y docker-ce docker-ce-cli docker-buildx-plugin docker-ce-rootless-extras docker-compose-plugin containerd.io
sudo dnf autoremove -y

# 4. 잔여 데이터/설정 삭제
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/containerd
sudo rm -f /etc/yum.repos.d/docker-ce.repo
sudo groupdel docker
sudo dnf makecache

# 5. iptables/ip6tables 정리
sudo firewall-cmd --list-all
for cmd in iptables ip6tables; do
  for table in filter nat mangle raw; do
    sudo $cmd -t $table -F
    sudo $cmd -t $table -X
  done

  sudo $cmd -P INPUT ACCEPT
  sudo $cmd -P FORWARD ACCEPT
  sudo $cmd -P OUTPUT ACCEPT
done

# 6. 고아 브리지 인터페이스 삭제
sudo ip link delete docker0
sudo ip link 
```

k3s 설치
```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --kube-controller-manager-arg=bind-address=0.0.0.0 \
  --kube-scheduler-arg=bind-address=0.0.0.0 \
  --kube-proxy-arg=metrics-bind-address=0.0.0.0 \
  --write-kubeconfig-mode=644" sh 

tree -pug /usr/local/bin
/usr/local/bin
├── [lrwxrwxrwx root     root    ]  crictl -> k3s
├── [lrwxrwxrwx root     root    ]  ctr -> k3s
├── [-rwxr-xr-x root     root    ]  k3s
├── [-rwxr-xr-x root     root    ]  k3s-killall.sh
├── [-rwxr-xr-x root     root    ]  k3s-uninstall.sh
└── [lrwxrwxrwx root     root    ]  kubectl -> k3s

cat /etc/systemd/system/k3s.service
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
User=root
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
    server \
        '--kube-controller-manager-arg=bind-address=0.0.0.0' \
        '--kube-scheduler-arg=bind-address=0.0.0.0' \
        '--kube-proxy-arg=metrics-bind-address=0.0.0.0' \
        '--write-kubeconfig-mode=644' \


systemctl is-active k3s.service
active

kubectl cluster-info -v=6
I0911 05:35:08.392158   36550 loader.go:407] Config loaded from file:  /etc/rancher/k3s/k3s.yaml
I0911 05:35:08.397727   36550 round_trippers.go:632] "Response" verb="GET" url="https://127.0.0.1:6443/api?timeout=32s" status="200 OK" milliseconds=4
I0911 05:35:08.401575   36550 round_trippers.go:632] "Response" verb="GET" url="https://127.0.0.1:6443/apis?timeout=32s" status="200 OK" milliseconds=1
I0911 05:35:08.441403   36550 round_trippers.go:632] "Response" verb="GET" url="https://127.0.0.1:6443/api/v1/namespaces/kube-system/services?labelSelector=kubernetes.io%2Fcluster-service%3Dtrue" status="200 OK" milliseconds=31
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy
To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.


cat /etc/rancher/k3s/k3s.yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdGMyVnkKZG1WeUxXTmhRREUzT0RreE1EUTRNREF3SGhjTk1qWXdPVEV4TURRek16SXdXaGNOTXpZd09UQTRNRFF6TXpJdwpXakFqTVNFd0h3WURWUVFEREJock0zTXRjMlZ5ZG1WeUxXTmhRREUzT0RreE1EUTRNREF3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFTUmhxWTBRSDNlRUYyUHNPY0dxQTcwUDNEakxLUkFDOUUvRXgvaS8ranUKUTZ0ZHVCa0dJdk04UG02VjM1dnJqT28zWjBjM2UwMTcvdWhFMjlmOEtYUDdvMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVTdaMDU4alJWRnNyUmdyRjlKTnBIClQzd1pQbjh3Q2dZSUtvWkl6ajBFQXdJRFNBQXdSUUloQU5wRzZuMnFEVWg2U3hkeVE3aW93WWh5NnJFcG1vRkIKTFpqeXh6NitQeVBBQWlCS01LVytDMHpRcnBkWXR3V0dlTk04aGVqSjllRmdsWkY5Q3BvOEZEK1E3QT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
kind: Config
users:
- name: default
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJrakNDQVRlZ0F3SUJBZ0lJV0tiRFdKQis3eEV3Q2dZSUtvWkl6ajBFQXdJd0l6RWhNQjhHQTFVRUF3d1kKYXpOekxXTnNhV1Z1ZEMxallVQXhOemc1TVRBME9EQXdNQjRYRFRJMk1Ea3hNVEEwTXpNeU1Gb1hEVEkzTURreApNVEEwTXpNeU1Gb3dNREVYTUJVR0ExVUVDaE1PYzNsemRHVnRPbTFoYzNSbGNuTXhGVEFUQmdOVkJBTVRESE41CmMzUmxiVHBoWkcxcGJqQlpNQk1HQnlxR1NNNDlBZ0VHQ0NxR1NNNDlBd0VIQTBJQUJON2dkeHd1S0lhd21RWUEKTnByRVFjZ1JibGZPeEE4OW4yclBDbGVGb01UUWFOS2dJanhybERoZUNNcXdaUXYrMDYxclpJc0UxY3djUW82cApJK3U1VStXalNEQkdNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUtCZ2dyQmdFRkJRY0RBakFmCkJnTlZIU01FR0RBV2dCVFNDOElEd1BweTFCUjVIMTFhN285VkpmblN0REFLQmdncWhrak9QUVFEQWdOSkFEQkcKQWlFQTlHYU9XOVg3VncxVG11a01kaERLSFVCd3ZSandSQ0lodWIyRG5WREUxUHdDSVFDaWs2N0xxazRxL1JyNwphSUVTekFRVU15cGlraHV4VG0reUV1bkhWS2FZYmc9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCi0tLS0tQkVHSU4gQ0VSVElGSUNBVEUtLS0tLQpNSUlCZHpDQ0FSMmdBd0lCQWdJQkFEQUtCZ2dxaGtqT1BRUURBakFqTVNFd0h3WURWUVFEREJock0zTXRZMnhwClpXNTBMV05oUURFM09Ea3hNRFE0TURBd0hoY05Nall3T1RFeE1EUXpNekl3V2hjTk16WXdPVEE0TURRek16SXcKV2pBak1TRXdId1lEVlFRRERCaHJNM010WTJ4cFpXNTBMV05oUURFM09Ea3hNRFE0TURBd1dUQVRCZ2NxaGtqTwpQUUlCQmdncWhrak9QUU1CQndOQ0FBUzdLS2MvOXM0OUo1VmFoeW1KUEZOazJpb1pmTlhYdHd4ZFdaN3dzeFEwCnQ1d0xwaXNGdDY4MTFoTkR4K0t6OENKRlk3K2dNbGN4dmtwUkFqb1ZhZU9rbzBJd1FEQU9CZ05WSFE4QkFmOEUKQkFNQ0FxUXdEd1lEVlIwVEFRSC9CQVV3QXdFQi96QWRCZ05WSFE0RUZnUVUwZ3ZDQThENmN0UVVlUjlkV3U2UApWU1g1MHJRd0NnWUlLb1pJemowRUF3SURTQUF3UlFJZ1JjWXQzQldnU0sxVWRrSlQxdHB6TGtsTlZUQnEzeTZjCkU2czJzanIrOE1rQ0lRRGpXbWpIclBZOC95S21JU2RFMlhpTExnUElYbVlpR2pXOVFoOWlmV3N6OUE9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    client-key-data: LS0tLS1CRUdJTiBFQyBQUklWQVRFIEtFWS0tLS0tCk1IY0NBUUVFSUYwRVNpTEc5UlRmaUVKMk52MHE4ckw4ZmdQQytsR3NFbW11TzZ4czdGRjFvQW9HQ0NxR1NNNDkKQXdFSG9VUURRZ0FFM3VCM0hDNG9ockNaQmdBMm1zUkJ5QkZ1Vjg3RUR6MmZhczhLVjRXZ3hOQm8wcUFpUEd1VQpPRjRJeXJCbEMvN1RyV3RraXdUVnpCeENqcWtqNjdsVDVRPT0KLS0tLS1FTkQgRUMgUFJJVkFURSBLRVktLS0tLQo=

ln -s /etc/rancher/k3s/k3s.yaml ~/.kube/config

kubectl get node -o wide
NAME            STATUS   ROLES           AGE    VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                                 CONTAINER-RUNTIME
hami-workshop   Ready    control-plane   2m1s   v1.36.4+k3s1   10.186.0.2    <none>        Rocky Linux 9.8 (Blue Onyx)   5.14.0-687.42.1+2.1.el9_8_ciq.x86_64 (amd64)   containerd://2.3.4-k3s1.36

# 컨테이너런타임 부분에 nvidia 인식한다.
# 해당 설정만으로는 부족하고, nvidia device plugin을 배포하여 gpu라는 k8s가 모르는 자원을 k8s 리소스에 노출시켜야 한다. 
sudo grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'nvidia']
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'nvidia'.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
  
kubectl get runtimeclass nvidia
NAME     HANDLER   AGE
nvidia   nvidia    2m23s

kubectl describe node | grep -i '^Taints'
Taints:             <none>
```

nvida device plugin 설치
```sh
curl -sL https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.20.0/deployments/static/nvidia-device-plugin.yml -o nvidia-device-plugin.yml

sed -i "30a\\      runtimeClassName: nvidia" nvidia-device-plugin.yml

kubectl apply -f nvidia-device-plugin.yml

kubectl get ds -n kube-system nvidia-device-plugin-daemonset
NAME                             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
nvidia-device-plugin-daemonset   1         1         1       1            1           <none>          16s


kubectl get pod -n kube-system -l name=nvidia-device-plugin-ds
nvidia-device-plugin-daemonset-77dss   1/1     Running   0          28s


# Volumes을 보면 kubelet이 device plugin과 통신하기위해 디렉토리가 마운트 된것을 확인할 수가 있다.
# 이전에는 gpu를 사용하기 위해 모든 권한을 필요로 했지만, 현재는 특정 디렉토리만 마운트하여 gpu를 활용한다.
kubectl describe pod -n kube-system -l name=nvidia-device-plugin-ds
Name:                 nvidia-device-plugin-daemonset-77dss
..
Runtime Class Name:   nvidia
Labels:               controller-revision-hash=94d64b7f6
                      name=nvidia-device-plugin-ds
...
Controlled By:  DaemonSet/nvidia-device-plugin-daemonset
Containers:
  nvidia-device-plugin-ctr:
    Image:          nvcr.io/nvidia/k8s-device-plugin:v0.20.0
...
Volumes:
  kubelet-device-plugins-dir:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/kubelet/device-plugins
    HostPathType:  Directory
...
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  49s   default-scheduler  Successfully assigned kube-system/nvidia-device-plugin-daemonset-77dss to hami-workshop
  Normal  Pulling    49s   kubelet            spec.containers{nvidia-device-plugin-ctr}: Pulling image "nvcr.io/nvidia/k8s-device-plugin:v0.20.0"
  Normal  Pulled     43s   kubelet            spec.containers{nvidia-device-plugin-ctr}: Successfully pulled image "nvcr.io/nvidia/k8s-device-plugin:v0.20.0" in 6.116s (6.116s including waiting). Image size: 55104215 bytes.
  Normal  Created    43s   kubelet            spec.containers{nvidia-device-plugin-ctr}: Container created
  Normal  Started    43s   kubelet            spec.containers{nvidia-device-plugin-ctr}: Container started


ls -l /var/lib/kubelet/device-plugins
-rw-------. 1 root root 140 Sep 11 05:37 kubelet_internal_checkpoint
srwxr-xr-x. 1 root root   0 Sep 11 05:33 kubelet.sock
srwxr-xr-x. 1 root root   0 Sep 11 05:37 nvidia-gpu.sock

kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'; echo
1

kubectl describe node
Name:               hami-workshop
Roles:              control-plane
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/instance-type=k3s
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=hami-workshop
                    kubernetes.io/os=linux
                    node-role.kubernetes.io/control-plane=true
                    node.kubernetes.io/instance-type=k3s
Annotations:        alpha.kubernetes.io/provided-node-ip: 10.186.0.2
                    flannel.alpha.coreos.com/backend-data: {"VNI":1,"VtepMAC":"be:03:96:b1:c4:2b"}
                    flannel.alpha.coreos.com/backend-type: vxlan
                    flannel.alpha.coreos.com/kube-subnet-manager: true
                    flannel.alpha.coreos.com/public-ip: 10.186.0.2
                    k3s.io/hostname: hami-workshop
                    k3s.io/internal-ip: 10.186.0.2
                    k3s.io/node-args:
                      ["server","--kube-controller-manager-arg","bind-address=0.0.0.0","--kube-scheduler-arg","bind-address=0.0.0.0","--kube-proxy-arg","metrics...
                    k3s.io/node-config-hash: TGN6IK6FTQX6S5LQCZA357LMEFMOF7QULVYMAZ6IPY7VXK4I62OQ====
                    k3s.io/node-env: {}
                    node.alpha.kubernetes.io/ttl: 0
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Fri, 11 Sep 2026 05:33:28 +0000
Taints:             <none>
Unschedulable:      false
Lease:
  HolderIdentity:  hami-workshop
  AcquireTime:     <unset>
  RenewTime:       Fri, 11 Sep 2026 05:39:25 +0000
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  MemoryPressure   False   Fri, 11 Sep 2026 05:38:03 +0000   Fri, 11 Sep 2026 05:33:28 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Fri, 11 Sep 2026 05:38:03 +0000   Fri, 11 Sep 2026 05:33:28 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure      False   Fri, 11 Sep 2026 05:38:03 +0000   Fri, 11 Sep 2026 05:33:28 +0000   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready            True    Fri, 11 Sep 2026 05:38:03 +0000   Fri, 11 Sep 2026 05:33:28 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  10.186.0.2
  Hostname:    hami-workshop
Capacity:
  cpu:                4
  ephemeral-storage:  104585264Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             15075200Ki
  nvidia.com/gpu:     1
  pods:               110
Allocatable:
  cpu:                4
  ephemeral-storage:  101740544740
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             15075200Ki
  nvidia.com/gpu:     1
  pods:               110
System Info:
  Machine ID:                 07592d80d17648c99a9c5912e31941ac
  System UUID:                b265a404-0b0f-266c-0d4b-f4a3a8a73d7a
  Boot ID:                    184999cb-5902-48e9-85d7-dad4fd0aeb8a
  Kernel Version:             5.14.0-687.42.1+2.1.el9_8_ciq.x86_64
  OS Image:                   Rocky Linux 9.8 (Blue Onyx)
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://2.3.4-k3s1.36
  Kubelet Version:            v1.36.4+k3s1
PodCIDR:                      10.42.0.0/24
PodCIDRs:                     10.42.0.0/24
ProviderID:                   k3s://hami-workshop
Non-terminated Pods:          (6 in total)
  Namespace                   Name                                       CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                       ------------  ----------  ---------------  -------------  ---
  kube-system                 coredns-54996dc9b4-fwbpx                   100m (2%)     0 (0%)      70Mi (0%)        170Mi (1%)     5m56s
  kube-system                 local-path-provisioner-77b9867795-6zj87    0 (0%)        0 (0%)      0 (0%)           0 (0%)         5m56s
  kube-system                 metrics-server-6dc596dfb8-k67fk            100m (2%)     0 (0%)      70Mi (0%)        0 (0%)         5m56s
  kube-system                 nvidia-device-plugin-daemonset-77dss       0 (0%)        0 (0%)      0 (0%)           0 (0%)         104s
  kube-system                 svclb-traefik-c469ff20-5ntrh               0 (0%)        0 (0%)      0 (0%)           0 (0%)         5m41s
  kube-system                 traefik-59b7647586-dbnhx                   0 (0%)        0 (0%)      0 (0%)           0 (0%)         5m41s
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                200m (5%)   0 (0%)
  memory             140Mi (0%)  170Mi (1%)
  ephemeral-storage  0 (0%)      0 (0%)
  hugepages-1Gi      0 (0%)      0 (0%)
  hugepages-2Mi      0 (0%)      0 (0%)
  nvidia.com/gpu     0           0
Events:
  Type    Reason                          Age    From                   Message
  ----    ------                          ----   ----                   -------
  Normal  CertificateExpirationOK         6m3s   k3s-cert-monitor       Node and Certificate Authority certificates managed by k3s are OK
  Normal  Synced                          5m58s  cloud-node-controller  Node synced successfully
  Normal  RegisteredNode                  5m57s  node-controller        Node hami-workshop event: Registered Node hami-workshop in Controller
  Normal  NodePasswordValidationComplete  5m57s  k3s-supervisor         Deferred node password secret validation complete
"]

# helm 설치
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh

# k8s가 gpu를 자원으로 인식하기 위한 작업 진행
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --create-namespace \
  --set runtimeClassName=nvidia

# 테스트
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: default
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  containers:
  - name: gpu-test
    image: pytorch/pytorch:2.13.0-cuda13.2-cudnn9-runtime
    command: ["sleep", "infinity"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

kubectl exec -it gpu-test -- bash

env | grep NVIDIA
NVIDIA_VISIBLE_DEVICES=GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256
NVIDIA_DRIVER_CAPABILITIES=compute,utility

nvidia-smi
Fri Sep 11 05:55:47 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 615.71.09              KMD Version: 615.71.09     CUDA UMD Version: 13.4     |
|   0  Tesla T4                       On  |   00000000:00:04.0 Off |                    0 |

which nvidia-smi
/usr/bin/nvidia-smi

df -hT
Filesystem     Type     Size  Used Avail Use% Mounted on
overlay        overlay  100G   17G   84G  17% /
tmpfs          tmpfs     64M     0   64M   0% /dev
/dev/sda2      xfs      100G   17G   84G  17% /etc/hosts
shm            tmpfs     64M     0   64M   0% /dev/shm
tmpfs          tmpfs    2.9G  9.9M  2.9G   1% /run/nvidia-persistenced/socket
tmpfs          tmpfs     15G   12K   15G   1% /run/secrets/kubernetes.io/serviceaccount
tmpfs          tmpfs    4.0K  4.0K     0 100% /run/nvidia-ctk-hooke76b23ac-4e9f-4a52-9ccd-17de6ee203e7
tmpfs          tmpfs    7.2G     0  7.2G   0% /proc/acpi
tmpfs          tmpfs    7.2G     0  7.2G   0% /proc/scsi
tmpfs          tmpfs    7.2G     0  7.2G   0% /sys/firmware

ls -l /dev/nvidia*
crw-rw-rw-. 1 root root 195, 254 Sep 11 05:55 /dev/nvidia-modeset
crw-rw-rw-. 1 root root 234,   0 Sep 11 05:55 /dev/nvidia-uvm
crw-rw-rw-. 1 root root 234,   1 Sep 11 05:55 /dev/nvidia-uvm-tools
crw-rw-rw-. 1 root root 195,   0 Sep 11 05:55 /dev/nvidia0
crw-rw-rw-. 1 root root 195, 255 Sep 11 05:55 /dev/nvidiactl

/dev/nvidia-caps:
total 0
cr--------. 1 root root 238, 1 Sep 11 05:55 nvidia-cap1
cr--r--r--. 1 root root 238, 2 Sep 11 05:55 nvidia-cap2

ls -l /usr/lib/x86_64-linux-gnu/libcuda*
lrwxrwxrwx. 1 root root        12 Sep 11 05:55 /usr/lib64/libcuda.so -> libcuda.so.1
lrwxrwxrwx. 1 root root        20 Sep 11 05:55 /usr/lib64/libcuda.so.1 -> libcuda.so.615.71.09

ls -l /usr/lib/x86_64-linux-gnu/libnvidia*
lrwxrwxrwx. 1 root root        12 Sep 11 05:55 /usr/lib64/libcuda.so -> libcuda.so.1
lrwxrwxrwx. 1 root root        20 Sep 11 05:55 /usr/lib64/libcuda.so.1 -> libcuda.so.615.71.09

/usr/bin/python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
True Tesla T4

exit

kubectl delete pod gpu-test
```

### kube-promethues-stack

kube-prometheus-stack를 배포하며, 프로메테우스와 그라파나는 NodePort로 설정한다.   
프로메테우스 : 30001  
그라파나 : 30002   

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl get sc

# PC IP 변수 지정
export MYPCIP=$(hostname -I | awk '{print $1}')
echo $MYPCIP

cat <<EOT > monitor-values.yaml
prometheus:
  service:
    type: NodePort
    nodePort: 30001
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi


grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator
  service:
    type: NodePort
    nodePort: 30002
  persistence:
    enabled: true
    type: pvc
    storageClassName: local-path
    accessModes:
      - ReadWriteOnce
    size: 10Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi

prometheus-windows-exporter:
  prometheus:
    monitor:
      enabled: false
      
kubeControllerManager:
  enabled: true
  endpoints:
    - $MYPCIP
  service:
    enabled: true
    port: 10257
    targetPort: 10257
  serviceMonitor:
    enabled: true
    https: true
    insecureSkipVerify: true

kubeScheduler:
  enabled: true
  endpoints:
    - $MYPCIP
  service:
    enabled: true
    port: 10259
    targetPort: 10259
  serviceMonitor:
    enabled: true
    https: true
    insecureSkipVerify: true

kubeProxy:
  enabled: true
  endpoints:
    - $MYPCIP
  service:
    enabled: true
    port: 10249
    targetPort: 10249
  serviceMonitor:
    enabled: true

# etcd를 사용하지 않아 false 처리
kubeEtcd:
  enabled: false
EOT

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 87.5.1 \
  -f monitor-values.yaml --create-namespace --namespace monitoring

helm list -n monitoring
NAME                    NAMESPACE       REVISION        UPDATED                                        STATUS          CHART                           APP VERSION
kube-prometheus-stack   monitoring      1               2026-09-11 06:06:06.313995114 +0000 UTC        deployed        kube-prometheus-stack-87.5.1    v0.92.1

kubectl get pod -n monitoring
NAME                                                            READY   STATUS    RESTARTS   AGE
pod/alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          34s
pod/kube-prometheus-stack-grafana-ffb8dcc6b-f72kc               2/3     Running   0          40s
pod/kube-prometheus-stack-kube-state-metrics-5497db9c5c-mmmjh   1/1     Running   0          40s
pod/kube-prometheus-stack-operator-869dcd685c-hq7cm             1/1     Running   0          40s
pod/kube-prometheus-stack-prometheus-node-exporter-zgzsg        1/1     Running   0          40s
pod/prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          33s

NAME                                                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                         AGE
service/alertmanager-operated                            ClusterIP   None            <none>        9093/TCP,9094/TCP,9094/UDP      34s
service/kube-prometheus-stack-alertmanager               ClusterIP   10.43.45.200    <none>        9093/TCP,8080/TCP               40s
service/kube-prometheus-stack-grafana                    NodePort    10.43.69.222    <none>        80:30002/TCP                    40s
service/kube-prometheus-stack-kube-state-metrics         ClusterIP   10.43.91.90     <none>        8080/TCP                        40s
service/kube-prometheus-stack-operator                   ClusterIP   10.43.89.211    <none>        443/TCP                         40s
service/kube-prometheus-stack-prometheus                 NodePort    10.43.19.213    <none>        9090:30001/TCP,8080:30443/TCP   40s
service/kube-prometheus-stack-prometheus-node-exporter   ClusterIP   10.43.211.203   <none>        9100/TCP                        40s
service/prometheus-operated                              ClusterIP   None            <none>        9090/TCP                        33s

NODEPORT=$(kubectl get svc kube-prometheus-stack-grafana \
  -n monitoring \
  -o jsonpath='{.spec.ports[0].nodePort}')

# admin / prom-operator
open http://127.0.0.1:30002
```


### DCGM Exporter

그라파나에서 gpu 메트릭 정보를 수집하기 위해 DCGM Exporter를 배포한다.

그라파나 대쉬보드 uid는 `12239` 이다.

```sh
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts

helm repo update

helm upgrade --install dcgm-exporter nvidia/dcgm-exporter \
  -n monitoring \
  --set runtimeClassName=nvidia

kubectl -n monitoring port-forward svc/dcgm-exporter 9400:9400

curl -s http://localhost:9400/metrics | head -50
# HELP DCGM_FI_DEV_DEC_UTIL Decoder utilization (in %).
# TYPE DCGM_FI_DEV_DEC_UTIL gauge
DCGM_FI_DEV_DEC_UTIL{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 0
# HELP DCGM_FI_DEV_ENC_UTIL Encoder utilization (in %).
# TYPE DCGM_FI_DEV_ENC_UTIL gauge
DCGM_FI_DEV_ENC_UTIL{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 0

curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
# HELP DCGM_FI_DEV_GPU_UTIL GPU utilization (in %).
# TYPE DCGM_FI_DEV_GPU_UTIL gauge
DCGM_FI_DEV_GPU_UTIL{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 0

curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_FB_USED
# HELP DCGM_FI_DEV_FB_USED Framebuffer memory used (in MiB).
# TYPE DCGM_FI_DEV_FB_USED gauge
DCGM_FI_DEV_FB_USED{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 0

curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP
# HELP DCGM_FI_DEV_GPU_TEMP GPU temperature (in C).
# TYPE DCGM_FI_DEV_GPU_TEMP gauge
DCGM_FI_DEV_GPU_TEMP{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 43

curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_POWER_USAGE
# HELP DCGM_FI_DEV_POWER_USAGE Power draw (in W).
# TYPE DCGM_FI_DEV_POWER_USAGE gauge
DCGM_FI_DEV_POWER_USAGE{gpu="0",UUID="GPU-8f1f4d06-07fd-27a7-52d5-e58aa060d256",pci_bus_id="00000000:00:04.0",device="nvidia0",modelName="Tesla T4",hostname="hami-workshop",container="gpu-test",namespace="default",pod="gpu-test"} 15.507

curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_XID_ERRORS

# 부하 발생
# T4 기준으로 약 20분이 넘게 소요되엇다.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-load
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
  - name: cuda
    image: nvcr.io/nvidia/k8s/cuda-sample:nbody
    args: ["nbody", "-gpu", "-benchmark", "-numbodies=5000000"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

kubectl logs gpu-load 
Run "nbody -benchmark [-numbodies=<numBodies>]" to measure performance.
        -fullscreen       (run n-body simulation in fullscreen mode)
        -fp64             (use double precision floating point values for simulation)
        -hostmem          (stores simulation data in host memory)
        -benchmark        (run benchmark to measure performance)
        -numbodies=<N>    (number of bodies (>= 1) to run in simulation)
        -device=<d>       (where d=0,1,2.... for the CUDA device to use)
        -numdevices=<i>   (where i=(number of CUDA devices > 0) to use for simulation)
        -compare          (compares simulation results running once on the default GPU and once on the CPU)
        -cpu              (run n-body simulation on the CPU)
        -tipsy=<file.bin> (load a tipsy model file for simulation)

NOTE: The CUDA Samples are not meant for performance measurements. Results may vary when GPU Boost is enabled.

> Windowed mode
> Simulation data stored in video memory
> Single precision floating point simulation
> 1 Devices used for simulation
GPU Device 0: "Turing" with compute capability 7.5

> Compute 7.5 CUDA device: [Tesla T4]
Warning: "number of bodies" specified 5000000 is not a multiple of 256.
Rounding up to the nearest multiple: 5000192.
5000192 bodies, total time for 10 iterations: 1289499.875 ms
= 193.888 billion interactions per second
= 3877.770 single-precision GFLOP/s at 20 flops per interaction
```

### Nvdia GPU Operator
Kubernetes Node Feature Discovery를 설치하면, 하드웨어가 가지고 있는 기능을 자동으로 탐색하여 노드의 라벨로 추가해준다. 상세한 정보를 담고 있기에 좋을수도 잇지만, 라벨링을 통해 유의미한 문제를 해결하지 않는다면, etcd에 저장 공간 및 쿼리등 불필요한 데이터만 쌓을수 있다는 단점을 갖고 있다.

```sh
# 현재 노드에서 라벨을 조회하면 간단하 정보만 조회된다.
kubectl get node -o json | jq '.items[].metadata.labels'
{
  "beta.kubernetes.io/arch": "amd64",
  "beta.kubernetes.io/instance-type": "k3s",
  "beta.kubernetes.io/os": "linux",
  "kubernetes.io/arch": "amd64",
  "kubernetes.io/hostname": "hami-workshop",
  "kubernetes.io/os": "linux",
  "node-role.kubernetes.io/control-plane": "true",
  "node.kubernetes.io/instance-type": "k3s"
}

helm install -n node-feature-discovery --create-namespace nfd oci://registry.k8s.io/nfd/charts/node-feature-discovery --version 0.18.3

kubectl get pods -n node-feature-discovery
NAME                                                READY   STATUS    RESTARTS   AGE
nfd-node-feature-discovery-gc-65697d9d5-n6hmb       1/1     Running   0          16s
nfd-node-feature-discovery-master-dddf99db8-xjtwr   1/1     Running   0          16s
nfd-node-feature-discovery-worker-fqczw             1/1     Running   0          16s

# 이전과 다르게 다양한 라벨링이 추가되엇다.
kubectl get node --show-labels
hami-workshop   Ready    control-plane   131m   v1.36.4+k3s1   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/instance-type=k3s,beta.kubernetes.io/os=linux,feature.node.kubernetes.io/cpu-cpuid.ADX=true,feature.node.kubernetes.io/cpu-cpuid.AESNI=true,feature.node.kubernetes.io/cpu-cpuid.AVX2=true,feature.node.kubernetes.io/cpu-cpuid.AVX=true,feature.node.kubernetes.io/cpu-cpuid.CMPXCHG8=true,feature.node.kubernetes.io/cpu-cpuid.FMA3=true,feature.node.kubernetes.io/cpu-cpuid.FXSR=true,feature.node.kubernetes.io/cpu-cpuid.FXSROPT=true,feature.node.kubernetes.io/cpu-cpuid.HLE=true,feature.node.kubernetes.io/cpu-cpuid.HYPERVISOR=true,feature.node.kubernetes.io/cpu-cpuid.IA32_ARCH_CAP=true,feature.node.kubernetes.io/cpu-cpuid.IBPB=true,feature.node.kubernetes.io/cpu-cpuid.LAHF=true,feature.node.kubernetes.io/cpu-cpuid.MD_CLEAR=true,feature.node.kubernetes.io/cpu-cpuid.MOVBE=true,feature.node.kubernetes.io/cpu-cpuid.OSXSAVE=true,feature.node.kubernetes.io/cpu-cpuid.RTM=true,feature.node.kubernetes.io/cpu-cpuid.SPEC_CTRL_SSBD=true,feature.node.kubernetes.io/cpu-cpuid.STIBP=true,feature.node.kubernetes.io/cpu-cpuid.SYSCALL=true,feature.node.kubernetes.io/cpu-cpuid.SYSEE=true,feature.node.kubernetes.io/cpu-cpuid.X87=true,feature.node.kubernetes.io/cpu-cpuid.XSAVE=true,feature.node.kubernetes.io/cpu-cpuid.XSAVEOPT=true,feature.node.kubernetes.io/cpu-hardware_multithreading=true,feature.node.kubernetes.io/cpu-model.family=6,feature.node.kubernetes.io/cpu-model.id=79,feature.node.kubernetes.io/cpu-model.vendor_id=Intel,feature.node.kubernetes.io/kernel-config.NO_HZ=true,feature.node.kubernetes.io/kernel-config.NO_HZ_FULL=true,feature.node.kubernetes.io/kernel-selinux.enabled=true,feature.node.kubernetes.io/kernel-version.full=5.14.0-687.42.1_2.1.el9_8_ciq.x86_64,feature.node.kubernetes.io/kernel-version.major=5,feature.node.kubernetes.io/kernel-version.minor=14,feature.node.kubernetes.io/kernel-version.revision=0,feature.node.kubernetes.io/pci-0302_10de.present=true,feature.node.kubernetes.io/storage-nonrotationaldisk=true,feature.node.kubernetes.io/system-os_release.ID=rocky,feature.node.kubernetes.io/system-os_release.VERSION_ID.major=9,feature.node.kubernetes.io/system-os_release.VERSION_ID.minor=8,feature.node.kubernetes.io/system-os_release.VERSION_ID=9.8,kubernetes.io/arch=amd64,kubernetes.io/hostname=hami-workshop,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=true,node.kubernetes.io/instance-type=k3s

kubectl get node -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("feature.node.kubernetes.io/")))'
{
  "feature.node.kubernetes.io/cpu-cpuid.ADX": "true",
  "feature.node.kubernetes.io/cpu-cpuid.AESNI": "true",
  "feature.node.kubernetes.io/cpu-cpuid.AVX": "true",
  "feature.node.kubernetes.io/cpu-cpuid.AVX2": "true",
  "feature.node.kubernetes.io/cpu-cpuid.CMPXCHG8": "true",
  "feature.node.kubernetes.io/cpu-cpuid.FMA3": "true",
  "feature.node.kubernetes.io/cpu-cpuid.FXSR": "true",
  "feature.node.kubernetes.io/cpu-cpuid.FXSROPT": "true",
  "feature.node.kubernetes.io/cpu-cpuid.HLE": "true",
  "feature.node.kubernetes.io/cpu-cpuid.HYPERVISOR": "true",
  "feature.node.kubernetes.io/cpu-cpuid.IA32_ARCH_CAP": "true",
  "feature.node.kubernetes.io/cpu-cpuid.IBPB": "true",
  "feature.node.kubernetes.io/cpu-cpuid.LAHF": "true",
  "feature.node.kubernetes.io/cpu-cpuid.MD_CLEAR": "true",
  "feature.node.kubernetes.io/cpu-cpuid.MOVBE": "true",
  "feature.node.kubernetes.io/cpu-cpuid.OSXSAVE": "true",
  "feature.node.kubernetes.io/cpu-cpuid.RTM": "true",
  "feature.node.kubernetes.io/cpu-cpuid.SPEC_CTRL_SSBD": "true",
  "feature.node.kubernetes.io/cpu-cpuid.STIBP": "true",
  "feature.node.kubernetes.io/cpu-cpuid.SYSCALL": "true",
  "feature.node.kubernetes.io/cpu-cpuid.SYSEE": "true",
  "feature.node.kubernetes.io/cpu-cpuid.X87": "true",
  "feature.node.kubernetes.io/cpu-cpuid.XSAVE": "true",
  "feature.node.kubernetes.io/cpu-cpuid.XSAVEOPT": "true",
  "feature.node.kubernetes.io/cpu-hardware_multithreading": "true",
  "feature.node.kubernetes.io/cpu-model.family": "6",
  "feature.node.kubernetes.io/cpu-model.id": "79",
  "feature.node.kubernetes.io/cpu-model.vendor_id": "Intel",
  "feature.node.kubernetes.io/kernel-config.NO_HZ": "true",
  "feature.node.kubernetes.io/kernel-config.NO_HZ_FULL": "true",
  "feature.node.kubernetes.io/kernel-selinux.enabled": "true",
  "feature.node.kubernetes.io/kernel-version.full": "5.14.0-687.42.1_2.1.el9_8_ciq.x86_64",
  "feature.node.kubernetes.io/kernel-version.major": "5",
  "feature.node.kubernetes.io/kernel-version.minor": "14",
  "feature.node.kubernetes.io/kernel-version.revision": "0",
  "feature.node.kubernetes.io/pci-0302_10de.present": "true",
  "feature.node.kubernetes.io/storage-nonrotationaldisk": "true",
  "feature.node.kubernetes.io/system-os_release.ID": "rocky",
  "feature.node.kubernetes.io/system-os_release.VERSION_ID": "9.8",
  "feature.node.kubernetes.io/system-os_release.VERSION_ID.major": "9",
  "feature.node.kubernetes.io/system-os_release.VERSION_ID.minor": "8"
}

# pic 정보 조회
kubectl get node -o json | jq '.items[].metadata.labels | with_entries(select(.key | contains("pci")))'
{}
  "feature.node.kubernetes.io/pci-0302_10de.present": "true"
}

kubectl get node -o json | jq '.items[].metadata.labels | with_entries(select((.key | ascii_downcase | contains("nvidia")) or (.key | contains("10de"))))'
{
  "feature.node.kubernetes.io/pci-0302_10de.present": "true"
}

# NVIDIA Device Plugin을 Kubernetes에 설치하면서 NVIDIA RuntimeClass와 GPU Feature Discovery 활성화
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin -n kube-system \
  --set runtimeClassName=nvidia --set gfd.enabled=true

helm get values -n kube-system nvidia-device-plugin
USER-SUPPLIED VALUES:
gfd:
  enabled: true
runtimeClassName: nvidia

# gpu에 대한 라벨링도 조회가 가능하다. 
kubectl get node -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("nvidia.com/")))'
{
  "nvidia.com/cuda.driver-version.full": "615.71.09",
  "nvidia.com/cuda.driver-version.major": "615",
  "nvidia.com/cuda.driver-version.minor": "71",
  "nvidia.com/cuda.driver-version.revision": "09",
  "nvidia.com/cuda.driver.major": "615",
  "nvidia.com/cuda.driver.minor": "71",
  "nvidia.com/cuda.driver.rev": "09",
  "nvidia.com/cuda.runtime-version.full": "13.4",
  "nvidia.com/cuda.runtime-version.major": "13",
  "nvidia.com/cuda.runtime-version.minor": "4",
  "nvidia.com/cuda.runtime.major": "13",
  "nvidia.com/cuda.runtime.minor": "4",
  "nvidia.com/gfd.timestamp": "1789112881",
  "nvidia.com/gpu.compute.major": "7",
  "nvidia.com/gpu.compute.minor": "5",
  "nvidia.com/gpu.count": "1",
  "nvidia.com/gpu.family": "turing",
  "nvidia.com/gpu.machine": "Google-Compute-Engine",
  "nvidia.com/gpu.memory": "15360",
  "nvidia.com/gpu.mode": "compute",
  "nvidia.com/gpu.product": "Tesla-T4",
  "nvidia.com/gpu.replicas": "1",
  "nvidia.com/gpu.sharing-strategy": "none",
  "nvidia.com/mig.capable": "false",
  "nvidia.com/mps.capable": "false",
  "nvidia.com/vgpu.present": "false"
}

helm uninstall -n kube-system nvidia-device-plugin
helm uninstall -n node-feature-discovery nfd
kubectl delete namespace node-feature-discovery
```

```sh
# TS
# 이 상태(Capacity/Allocatable 불일치)는 보통 device-plugin 파드를 재시작하거나, 그래도 안 되면 kubelet(k3s) 자체를 재시작해야 Allocatable이 다시 동기화된다.
kubectl delete pod -n kube-system nvidia-device-plugin-daemonset-77dss
sudo systemctl restart k3s
```

### vLLM 배포

- vllm ns 생성, vllm/vllm-openai:v0.28.0 이미지 활용하여 vllm 서빙
  - --served-model-name skt/A.X-4.0-Light
  - --load-format runai_streamer
  - --max-model-len 8192
  - --enable-auto-tool-choice
  - --tool-call-parser hermes
- minio에 `skt/A.X-4.0-Light` 모델을 저장하여 모델 로딩, 모델 크기 약 13.53
  - port : 30003
- vllm
  - port : 30005

> 작업하고나서 안 사실이지만, l4 16GB만으로 돌리기엔느 계속해서 OOM 문제로 실행하지 못했다

```sh
# minio 배포
kubectl create namespace vllm

kubectl create secret generic minio-credentials \
  -n vllm \
  --from-literal=MINIO_ROOT_USER=minioadmin \
  --from-literal=MINIO_ROOT_PASSWORD=minioadmin

kubectl create secret generic hf-token \
  -n vllm \
  --from-literal=HF_TOKEN=''

cat > minio.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: vllm
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 30Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: vllm
spec:
  replicas: 1
  selector:
    matchLabels: { app: minio }
  template:
    metadata:
      labels: { app: minio }
    spec:
      containers:
        - name: minio
          image: minio/minio:latest
          args: ["server", "/data", "--console-address", ":9001"]
          envFrom:
            - secretRef: { name: minio-credentials }
          ports:
            - containerPort: 9000
              name: api
            - containerPort: 9001
              name: console
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim: { claimName: minio-data }
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: vllm
spec:
  selector: { app: minio }
  ports:
    - name: api
      port: 9000
      targetPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: vllm
spec:
  type: NodePort
  selector: { app: minio }
  ports:
    - name: console
      port: 9001
      targetPort: 9001
      nodePort: 30003
EOF

kubectl apply -f minio.yaml

kubectl get pvc -n vllm
NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
minio-data   Bound    pvc-442e72c0-60d2-4465-aff3-55a7b15ec42c   30Gi       RWO            local-path     <unset>                 22m

kubectl get pv | grep vllm/minio-data
pvc-442e72c0-60d2-4465-aff3-55a7b15ec42c   30Gi       RWO            Delete           Bound    vllm/minio-data                                                                                                   local-path     <unset>                          22m

# 모델 다운로드 job
cat > job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: model-loader
  namespace: vllm
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: hf-download
          image: python:3.12-slim
          command:
            - sh
            - -c
            - |
              set -eu
              pip install --no-cache-dir -U "huggingface_hub[cli]"
              hf download skt/A.X-4.0-Light \
                --local-dir /model --token "$HF_TOKEN"
          env:
            - name: HF_TOKEN
              valueFrom: { secretKeyRef: { name: hf-token, key: HF_TOKEN } }
          volumeMounts:
            - name: model
              mountPath: /model
      containers:
        - name: s3-upload
          image: quay.io/minio/mc:latest # minio/mc:latest
          command:
            - sh
            - -c
            - |
              set -eu
              mc alias set localminio http://minio.vllm.svc.cluster.local:9000 \
                "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing localminio/models
              mc mirror --overwrite /model localminio/models/A.X-4.0-Light
          envFrom:
            - secretRef: { name: minio-credentials }
          volumeMounts:
            - name: model
              mountPath: /model
      volumes:
        - name: model
          emptyDir:
            sizeLimit: 20Gi
EOF

kubectl apply -f job.yaml

kubectl get job -n vllm
NAME           STATUS     COMPLETIONS   DURATION   AGE
model-loader   Complete   1/1           3m35s      3m40s

# 모델 다운로드 로그 확인 
kubectl logs -n vllm model-loader-zv6cl
Defaulted container "s3-upload" out of: s3-upload, hf-download (init)
Added `localminio` successfully.
Bucket created successfully `localminio/models`.
`/model/.cache/huggingface/.gitignore` -> `localminio/models/A.X-4.0-Light/.cache/huggingface/.gitignore`
`/model/.cache/huggingface/CACHEDIR.TAG` -> `localminio/models/A.X-4.0-Light/.cache/huggingface/CACHEDIR.TAG`
...
`/model/vocab.json` -> `localminio/models/A.X-4.0-Light/vocab.json`
┌───────────┬─────────────┬──────────┬──────────────┐
│ Total     │ Transferred │ Duration │ Speed        │
│ 13.53 GiB │ 13.53 GiB   │ 01m48s   │ 127.30 MiB/s │
└───────────┴─────────────┴──────────┴──────────────┘

# 실행에 약 4분 소요
cat > vllm.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-server
  namespace: vllm
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels: { app: vllm-server }
  template:
    metadata:
      labels: { app: vllm-server }
    spec:
      runtimeClassName: nvidia
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.28.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              python3 -c "import runai_model_streamer" 2>/dev/null || pip install --no-cache-dir vllm[runai]
              exec vllm serve s3://models/A.X-4.0-Light \
                --served-model-name skt/A.X-4.0-Light \
                --load-format runai_streamer \
                --host 0.0.0.0 --port 8000 \
                --max-model-len 1024 \
                --enforce-eager \
                --enable-auto-tool-choice \
                --tool-call-parser hermes
          env:
            - name: AWS_ENDPOINT_URL
              value: http://minio.vllm.svc.cluster.local:9000
            - name: AWS_EC2_METADATA_DISABLED
              value: "true"
            - name: RUNAI_STREAMER_S3_USE_VIRTUAL_ADDRESSING
              value: "0"
            - name: AWS_ACCESS_KEY_ID
              valueFrom: { secretKeyRef: { name: minio-credentials, key: MINIO_ROOT_USER } }
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom: { secretKeyRef: { name: minio-credentials, key: MINIO_ROOT_PASSWORD } }
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
          volumeMounts:
            - name: shm
              mountPath: /dev/shm
      volumes:
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-server
  namespace: vllm
spec:
  type: NodePort
  selector: { app: vllm-server }
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30005
EOF

kubectl apply -f vllm.yaml

kubectl get deploy,svc -n vllm vllm-server
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/vllm-server   1/1     1            1           4m12s

NAME                  TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)          AGE
service/vllm-server   NodePort   10.43.37.93   <none>        8000:30005/TCP   4m12s


# 모델 정보 호출
export MY_IP=$(curl -4 -s ifconfig.me)
curl -s http://$MY_IP:30005/v1/models | python3 -m json.tool

curl -s http://$MY_IP:30005/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "skt/A.X-4.0-Light",
    "messages": [
      {"role": "user", "content": "한국의 수도는 어디야?"}
    ],
    "max_tokens": 50
  }' | jq .choices

curl -N http://$MY_IP:30005/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "skt/A.X-4.0-Light",
    "messages": [{"role": "user", "content": "한국의 수도는 어디야?"}],
    "max_tokens": 50,
    "stream": true
  }'

cat > open-web-ui.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: open-webui-data
  namespace: vllm
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open-webui
  namespace: vllm
spec:
  replicas: 1
  selector:
    matchLabels: { app: open-webui }
  template:
    metadata:
      labels: { app: open-webui }
    spec:
      containers:
        - name: open-webui
          image: ghcr.io/open-webui/open-webui:main
          env:
            - name: OPENAI_API_BASE_URL
              value: http://vllm-server.vllm.svc.cluster.local:8000/v1
            - name: OPENAI_API_KEY
              value: dummy
            - name: WEBUI_AUTH
              value: "false"
            - name: ENABLE_OLLAMA_API
              value: "false"
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: data
              mountPath: /app/backend/data
      volumes:
        - name: data
          persistentVolumeClaim: { claimName: open-webui-data }
---
apiVersion: v1
kind: Service
metadata:
  name: open-webui
  namespace: vllm
spec:
  type: NodePort
  selector: { app: open-webui }
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30006
EOF

kubecyl apply -f open-web-ui.yaml

kubectl delete ns vllm
```

Reference
- https://docs.rockylinux.org/10/desktop/display/installing_nvidia_gpu_drivers/
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#with-dnf-rhel-centos-fedora-amazon-linux
- https://project-hami.io/tutorials/labs/online-install
- https://docs.cloud.google.com/sdk/docs/install-sdk?hl=ko#rpm
