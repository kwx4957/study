### git subtree
```sh
# 1. 외부 레포지토리 원격지 등록
git remote add k8s-deploy https://github.com/kwx4957/k8s-deploy.git

# 2. 외부 레포지토리 내 폴더 가져오기
git subtree add --prefix=cloudnet@/k8s-deploy k8s-deploy master --squash
```