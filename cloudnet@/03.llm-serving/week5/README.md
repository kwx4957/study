## LLM Serving 스터디 5주차 
### 
### 
### 
### 
### 
### 목차

- [1.환경 설정](#1-환경-설정)
- [2. vLLM 및 LM Cache 설치](2-vLLM-및-LM-Cache-설치)
- [3. LM Cache 동작 테스트](#3-lm-cache-동작-테스트)
- [4. LM Cache 실행 및 벤치](#4-lm-cache-실행-및-벤치)
  - [4.1 LM Cache bench bench test](#41-lm-cache-bench-bench-test)
- [5. LM Cache & vllm 실행](#5-lm-cache--vllm-실행)
- [6. vllm이 LM Cache 사용한 경우와 사용하지 않은 경우 비교](#6-vllm이-lm-cache-사용한-경우와-사용하지-않은-경우-비교)
  - [6.1 LM Cache 비활성화 로그](#61-lm-cache-비활성화-로그)
  - [6.2 LM Cache 활성화 로그](#62-lm-cache-활성화-로그)
- [7. vllm 요청 테스트](#7-vllm-요청-테스트)
  - [7.1 LM Cache 비활성화](#71-lm-cache-비활성화)
  - [7.2 LM Cache 활성화](#72-lm-cache-활성화)
  - [7.3 결과 정리](#73-결과-정리)
- [8. python 요청 변경](#8-python-요청-변경)
  - [8.1 LM Cache 활성화](#81-lm-cache-활성화)
  - [8.2 LM Cache 비활성화](#82-lm-cache-비활성화)
  - [8.3 결과 정리](#83-결과-정리)


### 크롬 환경 설정
chrome://chrome-urls/?host=chrome://tracing/#internal-debug-pages 접속하여 chrome://tracing 이 속해있는 항목이 활성화도어있는지 확인한다. 만일 안되었다면 활성화해전다.

<img width="304" height="614" alt="image" src="https://github.com/user-attachments/assets/9f314a85-ada9-4369-b752-3a059259cc66" />


chrome://tracing/
