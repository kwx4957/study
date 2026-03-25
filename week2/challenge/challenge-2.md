## 2. Configure TLS with Hubble
허블 릴레이가 배포되면 허블은 호스트 네트워크의 TCP 포트에서 수신 대기한다. 이를 통해 hubble Relay는 클러스터의 모든 Hubble 인스턴스와 통신이 가능하다. Hubble 인스턴스와 Hubble Relay 간의 통신은 TLS로 암호화된다.

구성 방식 종류
- Helm
- **Cert-manager**
- cilium'certgen(using k8s cronjob)

```sh
# cert-manager 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml

NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5fbb96f87c-4q4ht              1/1     Running   0          98s
cert-manager-cainjector-55ff785bb9-x9fv8   1/1     Running   0          98s
cert-manager-webhook-6fb4454664-vrgd5      1/1     Running   0          97s

# Cluseter-Issuer 생성
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}

# 서명 준비 완료
kubectl get clusterissuers -o wide selfsigned-cluster-issuer
NAME                READY   STATUS   AGE
selfsigned-cluster-issuer   True             4s
```

정리하자면 self-signed ClusterIssuer를 생성하고, 해당 ClusterIssuer를 참조하는 Certificate를 생성한다. 이후 CluuseterIssuer가 tls 발급하더라도 인증서가 unknown authority이라는 에러가 발생하지 않는다.
```sh
# 기존에 발급된 tls의 CA 조회
# 아직 CLI가 배포되지 않은 상태이지만 이전 값과 비교하기 위해 사용
kubectl exec -i -n kube-system deployment/hubble-cli -- openssl s_client -showcerts -servername ${SERVERNAME} -connect ${IP?}:4244   -CAfile /var/lib/hubble-relay/tls/hubble-server-ca.crt   -cert /var/lib/hubble-relay/tls/client.crt   -key /var/lib/hubble-relay/tls/client.key
...
depth=1 CN=Cilium CA
verify return:1
depth=0 CN=*.default.hubble-grpc.cilium.io
...

# self-signed를 위한 인증 발급 및 ClusterIssuer 생성
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-selfsigned-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: my-selfsigned-ca
  secretName: root-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: my-ca-issuer
spec:
  ca:
    secretName: root-secret

# helm 옵션 추가
helm upgrade cilium cilium/cilium -n kube-system --reuse-values \
   --set hubble.tls.auto.enabled=true \
   --set hubble.tls.auto.method=certmanager \
   --set hubble.tls.auto.certValidityDuration=1095 \
   --set hubble.tls.auto.certManagerIssuerRef.group="cert-manager.io" \
   --set hubble.tls.auto.certManagerIssuerRef.kind="ClusterIssuer" \
   --set hubble.tls.auto.certManagerIssuerRef.name="my-ca-issuer"

# 2개의 시크릿이 존재하며, 기존에 있던 시크릿들이 재갱신된다
kubectl get -n kube-system secrets |grep hubble
hubble-relay-client-certs       kubernetes.io/tls               3      18s
hubble-server-certs             kubernetes.io/tls               3      18s

# 설치 유효성 검사
kubectl get configmap -n kube-system cilium-config -oyaml | grep hubble-disable-tls
hubble-disable-tls: "false"

# hubble-cli 배포
# AMD64라면 그대로 진행하되, arm64이라면 이미지 오류가 발생한다. 따라서 cli 이미지를 quay.io/cilium/hubble:v1.16.4으로 변경해야 에러가 발생하지 않는다.
kubectl apply -n kube-system -f https://raw.githubusercontent.com/cilium/cilium/main/examples/hubble/hubble-cli.yaml

# hubble 서버 나열
kubectl exec -it -n kube-system deployment/hubble-cli -- \
hubble watch peers --server unix:///var/run/cilium/hubble.sock

PEER_ADDED   192.168.10.100:4244 k8s-ctr (TLS.ServerName: k8s-ctr.default.hubble-grpc.cilium.io)
PEER_ADDED   192.168.10.101:4244 k8s-w1 (TLS.ServerName: k8s-w1.default.hubble-grpc.cilium.io)
PEER_ADDED   192.168.10.102:4244 k8s-w2 (TLS.ServerName: k8s-w2.default.hubble-grpc.cilium.io)

# 첫 번째 허블 서버의 IP 및 서버 이름을 환경 변수로 설정
IP=192.168.10.100
SERVERNAME=k8s-ctr.default.hubble-grpc.cilium.io

# Hubbler Relay 클라이언트 인증서를 사용하여 첫 번째 피어에 연결. 클라이언트의 연결을 수락하는지 검증
kubectl exec -it -n kube-system deployment/hubble-cli -- \
hubble observe --server tls://${IP?}:4244 \
    --tls-server-name ${SERVERNAME?} \
    --tls-ca-cert-files /var/lib/hubble-relay/tls/hubble-server-ca.crt \
    --tls-client-cert-file /var/lib/hubble-relay/tls/client.crt \
    --tls-client-key-file /var/lib/hubble-relay/tls/client.key
    
Jul 26 11:32:04.364: 127.0.0.1:48522 (world) <> kube-system/coredns-674b8bbfcf-mvbdg (ID:8303) pre-xlate-rev TRACED (TCP)
Jul 26 11:32:04.568: 192.168.10.100:42432 (host) -> 192.168.10.102:10250 (remote-node) to-network FORWARDED (TCP Flags: SYN)
Jul 26 11:32:04.569: 192.168.10.100:42432 (host) -> 192.168.10.102:10250 (remote-node) to-network FORWARDED (TCP Flags: ACK)
Jul 26 11:32:04.569: 192.168.10.100:42432 (host) -> 192.168.10.102:10250 (remote-node) to-network FORWARDED (TCP Flags: ACK, PSH)

# 클라이언트 인증서 없이 쿼리 시도
# 당연히 연결을 거부한다.
kubectl exec -it -n kube-system deployment/hubble-cli -- \
hubble observe --server tls://${IP?}:4244 \
    --tls-server-name ${SERVERNAME?} \
    --tls-ca-cert-files /var/lib/hubble-relay/tls/hubble-server-ca.crt

failed to connect to 'tls://192.168.10.100:4244': context deadline exceeded: connection error: desc = "error reading server preface: remote error: tls: certificate required"
command terminated with exit code 1

# TLS 없이 연결 시도
# 연결 거부 응닶으로 정상적인 값이다. 
kubectl exec -it -n kube-system deployment/hubble-cli -- \
hubble observe --server ${IP?}:4244

failed to connect to '192.168.10.100:4244': context deadline exceeded: connection error: desc = "error reading server preface: EOF"
command terminated with exit code 1

# Hubble-cli 파드에 openssl 설치
kubectl exec -it -n kube-system deployment/hubble-cli -- apk add --update openssl

# openssl을 사용하여 TLS 연결 테스트
# 서버 인증서는 유효하나, 클라이언트 인증서가 제공되지 않아 연결이 거부된다.
kubectl exec -it -n kube-system deployment/hubble-cli -- \
openssl s_client -showcerts -servername ${SERVERNAME} -connect ${IP?}:4244 \
-CAfile /var/lib/hubble-relay/tls/hubble-server-ca.crt

200DC9AAC2F60000:error:0A00045C:SSL routines:ssl3_read_bytes:tlsv13 alert certificate required:ssl/record/rec_layer_s3.c:912:SSL alert number 116
command terminated with exit code 1

# 클라이언트 인증서와 키 제공
kubectl exec -i -n kube-system deployment/hubble-cli -- \
openssl s_client -showcerts -servername ${SERVERNAME} -connect ${IP?}:4244 \
  -CAfile /var/lib/hubble-relay/tls/hubble-server-ca.crt \
  -cert /var/lib/hubble-relay/tls/client.crt \
  -key /var/lib/hubble-relay/tls/client.key

# 출력 예시
# 기존에 발급된 cilium CA에서 my-selfsigned-ca 변경된다.
Server certificate
subject=CN=*.default.hubble-grpc.cilium.io
issuer=CN=my-selfsigned-ca
---
SSL handshake has read 1316 bytes and written 1755 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_128_GCM_SHA256
Server public key is 2048 bit
This TLS version forbids renegotiation.
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)

Post-Handshake New Session Ticket arrived:
Start Time: 1723744378
Timeout   : 7200 (sec)
Verify return code: 0 (ok)
Extended master secret: no
Max Early Data: 0
---
read R BLOCK


# hubble-cli 삭제
kubectl delete -n kube-system -f https://raw.githubusercontent.com/cilium/cilium/main/examples/hubble/hubble-cli.yaml
```
https://cert-manager.io/docs/configuration/selfsigned/   
https://docs.cilium.io/en/stable/observability/hubble/configuration/tls/   
https://github.com/cilium/cilium/blob/v1.17.6/install/kubernetes/cilium/values.yaml   

## TroubleShooting
1. cert-manager 구성 후 clusterIssuer에 생성에 그치는 것이 아닌 certificate를 생성까지 해야 한다. 그렇지 않을 경우 다음 에러가 발생한다. 그럼에도 에러가 발생한다. 왜냐하면 cluseetIssuer가 selfSigned 이기 때문이다. 따라서 해당 문제를 해결하기 위해 ClusterIssuer를 SelfSigned로 생성 후 해당 ClusterIssuer의 certifcate를 참조하는 CluseterIssuer를 생성해야 한다.

```sh
failed to connect to 'tls://192.168.1.205:4244': context deadline exceeded: connection error: desc = "transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate signed by unknown authority"
```

2. Hubble metrics with tls
```sh
# Hubble Metrics API에서 인증을 확인하려면, 클라이언트 인증서를 확인하는데 사용할 CA 인증서로 CM 생성 
kubectl -n kube-system create configmap hubble-metrics-ca --from-file=ca.crt

# Hhubble Metrics TLS 
# 하지만 1.17.6 버전에서는 mtls.name이 null로 예상하고 있다. 
helm upgrade cilium cilium/cilium -n kube-system --reuse-values \
  --set hubble.metrics.tls.enabled=true \
  --set hubble.metrics.tls.server.mtls.enabled=true 
  # --set hubble.metrics.tls.server.mtls.name="hubble-metrics-ca" 

# Metrics에 대한 부분은 어려워서 패스
curl -v https://localhost:9965

k get secrets -n kube-system  |grep hubble
hubble-metrics-server-certs     kubernetes.io/tls               3      4m43s
hubble-relay-client-certs       kubernetes.io/tls               3      53m
hubble-server-certs             kubernetes.io/tls               3      53m

# 해당 시크릿 자체가 존재하지 않는다.
kubectl -n kube-system get secret hubble-relay-server-certs -o jsonpath='{.data.ca\.crt}' | base64 -d > hubble-ca.crt

hubble observe --tls --tls-ca-cert-files ./hubble-ca.crt --tls-server-name hubble.hubble-relay.cilium.io

k delete -n kube-system cm hubble-metrics-ca
```