## 3. MTU 1450 의미는 무엇이고, 실제 환경에서는 고려해야 될 부분들은 어떤것이 있을까요? (참고) MTU, MSS - Blog


kubectl exec -it curl-pod -- ping -M do -s 1500 $WEBPOD
PING 172.20.2.77 (172.20.2.77) 1500(1528) bytes of data.
ping: sendmsg: Message too large

--- 172.20.2.77 ping statistics ---
3 packets transmitted, 0 received, +3 errors, 100% packet loss, time 2037ms