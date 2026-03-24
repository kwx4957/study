### git subtree
```sh
# 1. 외부 레포지토리 원격지 등록
git remote add upstream_repo https://github.com/kwx4957/cilium-study.git

# 2. 외부 레포지토리 내 폴더 가져오기
git subtree add --prefix=external_project upstream_repo main --squash
```