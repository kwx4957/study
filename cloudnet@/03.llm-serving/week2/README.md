## LLM Serving 2주차 
### 프로덕션급 모델 서빙이 왜 어려운가?

> 간단하게 말하자면 고민(선택) 사항이 너무 방대하기 때문이다.

1. 모델을 서빙하기 위해 어떤 환경의 모델을 선택할 것인가?
    1. 클라우드 벤더에서 제공하는 API 또는 서빙 환경
    2. 자체 인프라 구축 
        1. 어떤 환경에서 인프라를 구축할지?
2. 몇 개의 모델을 서빙 할 것인가?
    1. 단일의 모델 서빙
    2. 여러 개의 모델 서빙
3. 서빙을 위한 필수 조건
    1. 보안
    2. 사용자 인증
    3. 과금 정책
    4. 컴퓨팅 리소스 관리
    5. 네트워크
    6. GPU 최적화
    7. 실험
    8. 관측가능성
    9. 온콜
4. GPU 비용 최적화
    1. 배치
    2. 스트리밍
5. CPU와 GPU 워크로드 분리
6. 성능 측정 기준
    1. 지연시간
    2. 처리량
    3. End-to-end
    4. Time to first token 
    5. Inter-token latency

### 계층형 엔터프라이즈 모델 서빙 아키텍처

```
                         Client
                           │
                           ▼
┌──────────────────────────────────────────┐ 
│ 1. Public API                            │
│ Authentication / Rate Limit / Billing    │
│ Tenant / Routing / Security              │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 2. Resource Management                   │
│ GPU / CPU / Memory / Capacity / Quota    │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 3. Model Selection & Orchestration       │
│ Model Routing / Load Balancing           │
│ Speculative Decoding / Experimentation   │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 4. Distributed Serving                   │
│ Multi-GPU / Multi-Node / KV Cache        │
│ Prompt Cache / Cache-aware Routing       │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 5. Core Inference                        │
│ vLLM / Triton / TensorRT-LLM / SGLang   │
│ CUDA / FlashAttention / PagedAttention  │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 6. Model Optimization                    │
│ Quantization / Speculative Decoding      │
│ Kernel / Memory / Inference Optimization │
└──────────────────────┬───────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────┐
│ 7. Model                                │
│ Model Registry / Version / Artifact      │
│ Training → Validation → Production      │
└──────────────────────────────────────────┘
```

### 1계층 Public API

ChatGPT를 기준으로 설명하자면, 웹 UI형태의 서비스 또는 LLM 시스템이 앞단에서 가장 먼저 사용자(고객 or 개발자)를 마주하는 인터페이스라고 볼수 있다. 사용자가 요청을 보내면 가장 먼저 Public API 계층을 통과하게 되고, `사용자에 따라 인증 및 요청 제한, 보안 정책 등을 처리한다.

- Authentication
  - API Key에 대한 인증 요청 처리
- Authorization
  - 어떤 모델을 사용할수 있는가? 예들 들어 3만원대의 프로 요금제를 결제한 사용자가 10만원대 요금에서 사용가능할 모델을 사용하면 안되는 권한을 검증한다.     
- Rate Limit
- Tenant 
- Routing
- Security
- Billing
  - 사용자의 API 사용량을 계산한다.  

1계층에서 k8s가 담당하는 역할과 서비스에서 담당하는 역할을 분리한다면 다음과 같은 구조를 가질 것이다. 

```yaml
Kubernetes / Gateway
├── Gateway API
├── HTTPRoute
├── TLS
├── Routing
└── Rate Limit / Security

External / Platform Services
├── Identity Provider
├── API Key
├── WAF / DDoS
├── Billing
├── Usage
├── Kafka
└── Policy Management
```

1계층은 외부 요청을 내부 서비스로 전달하는 것이 아니라, `누가 요청했는지`, `사용할 수 있는 요청인지`, `얼마나 사용할 수 있는지`, 그리고 `사용한 자원을 어떻게 기록할 것인지`를 관리한다.

### 2계층 Resource Management

LLM을 실행하기 위해 필요한 인프라 자원을 관리한다. GPU 존재 여부보다 어떤 workload에 어떤 GPU를 할당할 것인가?

- CPU
- GPU
    - Node Affinity
    - Node Label
    - Taints / Tolerations
    - ResourceQuota
    - LimitRange
- Memory
- Storage
- Network
- Capacity

k8s는 다음과 같이 리소스를 관리할수 있다. GPU를 관리하는 방식이 다양한 방식이 있다. `MIG` 또는 `HAMI` H100과 같은 고비용의 GPU라면 논리적인 격리인 MIG가 제공되지만, 이 경우에 속하지 않은 경우 `HAMI` 와 같은 시분할 기법도 존재한다. 

### 3계층 Model Selection & Orchestration

가장 어렵다고 느낌 계층 중 하나이다. 사용자의 요청을 보고 어떤 모델을 사용할지 결정한다. 알 수 없는 미래에 대해 미래를 예측한다는 문장과 비슷하다고 느껴진다. 이는 입력 값에 대한 분석을 처리하는 기능도 추가로 요구되는 것으로 느껴져서 더욱 그러한 느낌을 받는다. 

개념 자체는 요청마다 비싼 모델로 연산하는 것이 아니라 요청의 특성이나 서비스 정책을 기반으로 모델을 선택한다. 

- Model Selection
- Model Routing
- Load Balancing
- Cost / Quality
- Priority
- A/B Test
- Speculative Decoding
    - LLM의 텍스트 생성 속도를 높이기 위한 추론 최적화 기법입니다. 작고 빠른 드래프트 모델(Draft Model)이 여러 개의 토큰을 먼저 예측하고, 크고 정확한 타깃 모델(Target Model)이 이를 한 번에 병렬로 검증하여 출력 품질 손실 없이 속도를 2~4배 향상시킵니다.

모델 선택

```
간단한 질문 ->  Small Model
일반적인 질문 -> Medium Model
복잡한 질문 -> Large Model
```

들어온 요청이 다음과 같다면, 해당 요청의 특성을 분석하여 적합한 모델로 라우팅한다. 문제는 각 GPU마다 보유한 KV Cache 또는 가용 자원, 레이턴시, 큐 길이등 다양한 조건에 대해 고려해야 한다. 이러한 고려사항을 기반으로 라우팅을 처리해야 한다. 동시에 A/B 테스트로 최적화 기능에 대해서 테스트를 진행한다. 

```yaml
# 사용자 요청 예시 
Request
├── Model: auto
├── Input tokens: 1,200
├── Max output tokens: 4,000
├── User: enterprise-A
├── Priority: high
├── Region: Seoul
└── SLA: < 2 sec
```

## 4계층 Distributed Serving

LLM을 실제로 여러 GPU 또는 여러 Node에 분산해서 실행하기 위한 환경을 구성한다. 

왜 필요한가? LLM 모델의 크기가 커지면서 GPU 하나에 모델 올릴수 없기때문이다. 

병렬화 기술

- Tensor Parallelism
    - 하나의 Layer 내부의 행렬 연산 자체를 여러 GPU가 나눠서 수행하는 것
- Pipeline Parallelism
    - 모델의 Layer를 여러 GPU에 나눠서, GPU들이 생산라인처럼 순서대로 처리하는 것. GPU 별로 특정 범위를 지정해 나눠 연산
- Data Parallelism
    - 모델은 GPU마다 똑같이 복제하고, 데이터를 나눠서 처리하는 방식
- Multi-GPU
    - 한 서버 안에 GPU가 여러 장 있는 것
- Multi-Node

비교 예시 

| 방식 | 모델 | 데이터 | 목적 |
| --- | --- | --- | --- |
| Data Parallelism | GPU마다 복제 | 분할 | 처리량 증가 |
| Tensor Parallelism | GPU 간 분할 | 같이 처리 | 큰 모델 실행 / 연산 병렬화 |
| Pipeline Parallelism | Layer 단위 분할 | 같이 처리 | 큰 모델을 여러 GPU에 배치 |

```yaml
# 모델이 GPU 한도를 초과한 경우
Model Weight = 160GB
GPU VRAM     = 80GB

Model
  ↓
┌───────────┐
│ GPU 0     │
│ GPU 1     │
│ GPU 2     │
│ GPU 3     │
└───────────┘
```

## 5계층 Core Inference

실제 LLM의 인터페이스 연산 수행 계층으로 이전 계층에서는 어떤 모델과 GPU를 사용할지 결정했다면, 여기에서는 실제로 모델을 GPU에 올리고 Token을 생성한다.

LLM Serving Framework 

- vLLM
- Triton
- TensorRT-LLM
- SGLang

다음과 같은 최적화 기법 사용

- Continuous Batching
    - 요청이 끝날 때까지 기다리지 않고, 처리 중간에 새로운 요청을 계속 배치 처리
- PagedAttention
    - LLM의 KV Cache를 메모리 페이지 단위 관리
- FlashAttention
    - Attention 연산을 GPU 메모리에 효율적으로 처리하도록 최적화한 알고리즘
- CUDA Kernel Optimization
    - GPU에서 실행되는 연산 코드를 CUDA Kernel 수준에서 최적화
- KV Cache

## 6계층 Model Optimization

모델을 다시 학습하지 않고 LLM inference에 필요한 연산량과 GPU 메모리 사용량을 줄이는 것을 목표이다. 해당 계층은 LLM 서빙 프레임워크가 이를 추상화하여 옵션 형태로 제공한다. 앞서 5계층에서 이야기한 최적화 기법과 동일한 이야기를 하고 있어서 동일한 계층으로 봐도 무방하지 않을까라는 생각을 한다. 그만큼 vLLM와 같은 프레임워크를 사용하는 이유라고 생각한다. 프레임워크가 추상화하여 제공하는 덕에 세부적인 기능을 알지 않아도 된다는 것. 하지만 이러한 기능들이 내부적으로 어떻게 동작하는지 이해한다면 이야기가 달라진다. 단순히 옵션을 활성화하는 것에서 끝나는 것이 아니라, 자신의 모델과 GPU 환경, 요청 패턴에 맞게 적절한 설정을 적용할 수 있기 때문이다. 즉 5계층은 `LLM을 어떻게 실행할 것인가?` 책임을 갖는다면 6계층은 `동일한 GPU 자원에 대한 효율성` 에 대한 책임을 갖는다고 생각한다.

최적화 기법

- Quantization
    - 모델의 숫자 표현을 FP16 → INT8/INT4처럼 낮춰서 모델 크기와 메모리 사용량 감소
- Speculative Decoding
    - 작은 모델이 먼저 답을 빠르게 예측하고, 큰 모델이 이를 검증하는 방식, 앞서 3계층과 중복된다.
- KV Cache Optimization
- Prefix Caching
    - 여러 요청에서 앞부분(Prefix) 이 동일하면 기존 KV Cache를 재사용
- FlashAttention
- Kernel Optimization
- Distillation

## 7계층 Model

실제 LLM Model과 Model Lifecycle을 관리하는 계층이다. 모델은 한 번 만들어지고 끝나는 것이 아니라 계속 새로운 버전이 만들어지기 때문에 모델의 버전과 배포 상태를 관리한다. 해당 계층은 마치 애플리케이션 버전 관리와 유사하다는 느낌을 받는다. 

- Model Registry
    - 컨테이너 레지스트리와 같이 모델을 관리하기 위한 레지스트리가 필요하다
    
    ```yaml
    Model Registry
    ┌──────────────┬────────┬────────────┬────────────┐
    │ Model        │ Version│ Quantization│ Status     │
    ├──────────────┼────────┼────────────┼────────────┤
    │ Qwen3-14B    │ v1     │ FP16        │ deprecated │
    │ Qwen3-14B    │ v2     │ FP8         │ production │
    │ Llama-70B    │ v1     │ FP8         │ production │
    │ Qwen-VL      │ v1     │ FP16        │ staging    │
    └──────────────┴────────┴────────────┴────────────┘
    ```
    
- Model Version
    - 모델에 대한 버전 관리, 모델 버전과 Inference 버전은 분리해야 한다.
    
    ```yaml
    Qwen3-14B
    ├── v1
    ├── v2
    └── v3
    ```
    
- Model Artifact
    - 실제 모델 파일을 관리한다.
    
    ```yaml
    Qwen3-14B
    ├── config.json
    ├── tokenizer.json
    ├── model-00001-of-00004.safetensors
    ├── model-00002-of-00004.safetensors
    ├── model-00003-of-00004.safetensors
    └── model-00004-of-00004.safetensors
    ```
    
- Model Metadata
    
    ```yaml
    # 모델 메타데이터 예시
    model:
      name: qwen3-14b
      version: v2
      architecture: transformer
      parameters: 14B
      context_length: 32768
      quantization: FP8
      framework: vLLM
      gpu:
        type: H100
        minimum: 1
      status: production
    ```
    
- Model Deployment
- Model Promotion
- Model Rollback

### 결론

각 계층이 가진 역할의 책임 범위와 인터페이스를 명확하게 정의해야한다. 그래야만 특정 조직의 변경이 다른 팀에 불필요하게 영향을 주는 것을 줄이고, 각 팀이 독립적으로 빠르게 시스템을 개선할 수 있다. LLM 서빙을 한다는 것은 기술적인 영역도 있지만, GPU의 고비용, 신뢰성, 사용자 경험등 다양한 것을 동시에 만족시키는 시스템을 지속적으로 발전시키는 것이다.
