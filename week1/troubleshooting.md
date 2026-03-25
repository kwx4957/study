### rockylinux/9 변경 시    

지원되지 않는 아키텍처 문제 발생. 사용하는 이미지는 rockylinux/9에서 bentto/rockylinu/9으로 변경
```sh
There was an error while executing `VBoxManage`, a CLI used by Vagrant
for controlling VirtualBox. The command and stderr is shown below.

Command: ["startvm", "a5a27bec-db2b-4546-b1bc-4c9796b8a07d", "--type", "headless"]

Stderr: VBoxManage: error: The VM session was aborted
VBoxManage: error: Details: code NS_ERROR_FAILURE (0x80004005), component SessionMachine, interface ISession

Callee RC:
VBOX_E_PLATFORM_ARCH_NOT_SUPPORTED (0x80bb0012)
```
https://github.com/hashicorp/vagrant/issues/13588
