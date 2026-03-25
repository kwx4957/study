## 10. Making Damn Vulnerable Web Application (DVWA) almost unhackable with Cilium and Tetragon

## DVWA  
DVWA는 매우 취약한 PHP/MYSQL 구성의 웹 애플리케이션으로 취약점에 대해서 간단한 테스트하기 위한 과정이다. 해당 글을 통해 Tetragon으로 어떻게 런타임 보안 구성을 할수 있는지 알아보자

```sh
kubectl create ns dvwa

# Mysql password 생성
kubectl create secret generic -n dvwa mysql --from-literal=mysql-root-password=$(openssl rand -hex 20) --from-literal=mysql-replication-password=$(openssl rand -hex 20) --from-literal=mysql-password=$(openssl rand -hex 20)

# 생성 조회
k get secrets -n dvwa

git clone https://github.com/CptOfEvilMinions/BlogProjects
cd BlogProjects/k8s-dvwa

# 14번째 줄 ansible/template 수정
vi templates/deployment.yaml
ansible.builtin.template: -> template:

# dvwa 배포 
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update 
helm dependency build
helm install dvwa . -n dvwa -f values.yaml

# php 서비스를 ClusterIP에서 NodePort로 바꾸기
k get svc -n dvwa
dvwa                  ClusterIP    10.96.82.165   <none>        80/TCP   113m

k edit svc dvwa -n dvwa
type: NodePort

# {NodeIP}:{NodePort}으로 접속한다. admin/password
# 접속 후에 좌측 메뉴 바의 Setup/Reset DB > Create/Reset Database 눌러 재구성 후 다시 로그인 준다.
open http://192.168.10.100:31353/login.php

# 이후 좌측 메뉴 바의 DVWA Security를 통해 보안 단계를 설정할 수 있다. 기본 단계는 Impossible으로 모든 보안 공격이 막혀있는 상태이다. tetragon을 테스트하기 위해서 low로 변경해주었다.
```

## Tetragon 설치
```sh
# tetragon CLI 설치 
curl -L https://github.com/cilium/tetragon/releases/latest/download/tetra-linux-amd64.tar.gz | tar -xz
sudo mv tetra /usr/local/bin

k port-forward -n kube-system ds/tetragon 54321:54321

# 동작 확인 
tetra status
Health Status: running

POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl get pod -n dvwa -l app.kubernetes.io/name=dvwa -o jsonpath='{.items[0].spec.nodeName}'))
echo $POD 

# dvwa가 수행되는 노드에서 tetragon의 이벤트를 조회한다.
k exec -it -n kube-system $POD -c tetragon -- tetra getevents -o compact -F "dvwa-mysql-*" --pod dvwa |grep -v -i mysql
```

### 1. command injection
```sh
# http://192.168.10.100:32721/login.php 접속 후 Command 동작 확인
# ping을 날림과 동시에 내 ip 주소에 조회에 대한 명령어도 실행된다
8.8.8.8;curl http://ifconfig.me
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=254 time=28.5 ms
--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3007ms
rtt min/avg/max/mdev = 28.395/28.449/28.503/0.049 ms
33.11.22.44

# Before
k exec -it -n kube-system $POD -c tetragon -- tetra getevents -o compact -F "dvwa-mysql-*" --pod dvwa |grep -v -i mysql
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;curl http://ifconfig.me"
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8 0
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/curl http://ifconfig.me
🔌 connect dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/curl tcp 111.21.3.54:40822 -> 34.160.111.145:80
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/curl http://ifconfig.me 0
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;curl http://ifconfig.me" 0

# 정책 생성
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v1alpha1
kind: TracingPolicyNamespaced
metadata:
  name: "command-line-injection"
  namespace: "dvwa"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/instance: dvwa
      app.kubernetes.io/name: dvwa
  kprobes:
  - call: "sys_execve"
    syscall: true
    return: true
    args:
    - index: 0
      type: "string" # file path
    returnArg:
      index: 0
      type: "int"
    returnArgAction: "Post"
    selectors:
    - matchPIDs:
      - operator: In
        followForks: true
        isNamespacePID: true
        values:
          - 1 # Apache root
      matchArgs:
      - index: 0
        operator: "NotEqual"
        values:
          - "/usr/bin/ping"
          - "/bin/sh"
      matchActions:
      - action: Override
        argError: -1
      - action: Post
EOF

k exec -it -n kube-system $POD -c tetragon -- tetra getevents -o compact -F "dvwa-mysql-*" --pod dvwa |grep -v -i mysql

# __x64_sys_execve가 실행되는 과정에서 종료가 되었다.
8.8.8.8;curl http://ifconfig.me
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;curl http://ifconfig.me"
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8 0
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;curl http://ifconfig.me" 126
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;curl http://ifconfig.me" 126

8.8.8.8;cp /etc/passwd /tmp/passwd
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;cp /etc/passwd /tmp/passwd"
🚀 process dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /usr/bin/ping -c 4 8.8.8.8 0
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;cp /etc/passwd /tmp/passwd" 126
❓ syscall dvwa/dvwa-659bc6b99b-ksvrw /bin/sh __x64_sys_execve
💥 exit    dvwa/dvwa-659bc6b99b-ksvrw /bin/sh -c "ping  -c 4 8.8.8.8;cp /etc/passwd /tmp/passwd" 126
```

### 2. File Inclusion(동작안함)
```sh
open http://192.168.10.100:32721/vulnerabilities/fi/?page=../../../../../../etc/passwd

# 계정 정보가 출력된다
root:x:0:0:root:/root:/bin/bash daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin bin:x:2:2:bin:/bin:/usr/sbin/nologin sys:x:3:3:sys:/dev:/usr/sbin/nologin sync:x:4:65534:sync:/bin:/bin/sync games:x:5:60:games:/usr/games:/usr/sbin/nologin man:x:6:12:man:/var/cache/man:/usr/sbin/nologin lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin mail:x:8:8:mail:/var/mail:/usr/sbin/
...

# 정책 생성
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v1alpha1
kind: TracingPolicyNamespaced
metadata:
  name: "block-non-var-www-file-access"
  namespace: "dvwa"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/instance: dvwa
      app.kubernetes.io/name: dvwa
  kprobes:
  - call: "security_file_open"
    syscall: false
    return: true
    args:
    - index: 0
      type: "file" # (struct file *) used for getting the path
    returnArg:
      index: 0
      type: "int"
    returnArgAction: "Post"
    selectors:
    - matchPIDs:
      - operator: In
        followForks: true
        isNamespacePID: true
        values:
          - 1 # Apache root
    - matchBinaries:
      - operator: "In"
        values:
        - "/usr/sbin/apache2"
      matchArgs:
      - index: 0
        operator: "NotPrefix"
        values:
        - "/var/www/html/"
        - "/tmp/sess_"
      matchActions:
      - action: Override
        argError: -2
      - action: Post
EOF

k get TracingPolicyNamespaced -n dvwa

k exec -it -n kube-system $POD -c tetragon -- tetra getevents -o compact -F "dvwa-mysql-*" --pod dvwa |grep -v -i mysql

kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/main/examples/tracingpolicy/filename_monitoring.yaml 

cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "file-monitoring"
spec:
  kprobes:
  - call: "security_file_permission"
    syscall: false
    return: true
    args:
    - index: 0
      type: "file" # (struct file *) used for getting the path
    - index: 1
      type: "int" # 0x04 is MAY_READ, 0x02 is MAY_WRITE
    returnArg:
      index: 0
      type: "int"
    returnArgAction: "Post"
    selectors:
    - matchArgs:      
      - index: 0
        operator: "Prefix"
        values:
        - "/etc/" # filenames to filter for
      - index: 1
        operator: "Equal"
        values:
        - "2" # filter by type of access (MAY_WRITE)
  - call: "security_mmap_file"
    syscall: false
    return: true
    args:
    - index: 0
      type: "file" # (struct file *) used for getting the path
    - index: 1
      type: "uint32" # the prot flags PROT_READ(0x01), PROT_WRITE(0x02), PROT_EXEC(0x04)
    - index: 2
      type: "nop" # the mmap flags (i.e. MAP_SHARED, ...)
    returnArg:
      index: 0
      type: "int"
    returnArgAction: "Post"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Prefix"
        values:
        - "/etc/" # filenames to filter for
  - call: "security_path_truncate"
    syscall: false
    return: true
    args:
    - index: 0
      type: "path" # (struct path *) used for getting the path
    returnArg:
      index: 0
      type: "int"
    returnArgAction: "Post"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Prefix"
        values:
        - "/etc/" # filenames to filter for
EOF
```


[DVWA](https://github.com/digininja/DVWA)    
[Tetragon-example](https://github.com/cilium/tetragon/tree/main/examples)  
[Blog](https://holdmybeersecurity.com/2024/07/24/making-damn-vulnerable-web-application-dvwa-almost-unhackable-with-cilium-and-tetragon/#more-11582)  