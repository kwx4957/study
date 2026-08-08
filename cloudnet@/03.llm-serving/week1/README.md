# vLLM on Colab T4

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/kwx4957/study/blob/master/03.llm-serving/week1/vllm_on_colab_t4.ipynb)

## 목표
LLM을 구성하는 복잡한 수식의 세부적인 원리를 규명하는 데 초점을 맞추기보다, 제한된 자원 환경에서 LLM의 성능을 개선하기 위해 LLM이 어떠한 방식으로 동작하며 어떤 비효율성을 내포하고 있는지를 분석하고, 이를 해결하기 위한 방향을 모색하여 향후 시스템을 어떻게 설계해야 하는지를 이해하는 데 중점을 둔다.

## 0. 단어 및 개념 정리
- Token : 사용자가 입력한 문장를 잘게 조깬다. 여기서 잘게 쪼개는 것은 단어가 될수도 있지만, 긴 단어일 경우 여러 개의 단어로 나눠질수도 있다.
  - "Artificial intelligence is amazing" > ["Artificial", " intelligence", " is", " amazing"]
- Token ID : 각 토큰을 나타내는 고유한 정수 번호, 해쉬 키 개념? 
  - "Artificial"     → 52341
- Vector : 토큰 하나를 숫자료 표현한 것으로 `hidden_size=896`이라면 하나의 토큰에 대해서 896개의 숫자료 표현한다.
  - [0.21, -0.84, 1.17, 0.03, ...]
- Hidden Size : 하나의 토큰을 몇 개의 숫자로 표현할 것인지를 의미한다. hidden_size=896이라면 트랜스포머 내부에서 하나의 토큰은 896차원의 벡터로 표현된다.
  - 토큰 1개 → 896개의 숫자
- Hidden State : 트랜스포머 내부에서 현재 토큰을 표현하고 있는 벡터 값이다. 처음에는 Embedding Vector(초기값)으로 시작하지만 트랜스포머 레이어를 통과할 때마다 주변 문맥을 반영하면서 값이 계속 변경된다.
  - "bank"라는 같은 토큰도 "river bank"와 "bank account"에서는 서로 다른 Hidden State를 가질 수 있다.
- Embedding : 토큰을 벡터로 표현하는 과정 내지 결과를 의미한다. 토큰을 벡터로 변환하는 이유는 신경망이 문자열 자체를 계산할 수 없기 때문이며, 학습 과정에서 비슷한 의미나 비슷한 문맥적 역할을 가진 토큰 비슷한 벡터 표현을 가지도록 하기 위해서이다.
  - Token → Token ID → Embedding Vector
- Transformer : 토큰의 벡터들을 입력받아 Token 간의 관계와 문맥을 계산하고, 각 토큰의 벡터를 새로운 값으로 변경하는 구조이다. 하나의 트랜스포머 블록은 어텐션과 FFN으로 구성되며, Block을 여러 개 쌓아서 사용한다.
  - Input → Attention → Add + Normalization → FFN → Add + Normalization → Output
- Transformer Block : 트랜스포머 내부의 반복되는 하나의 계산 단위이다. 모델의 num_hidden_layers=24라면 이런 Transformer Block이 24개가 존재한다.
  - Embedding → Block 1 → Block 2 → ... → Block 24
- Attention : 현재 토큰이 다른 토큰들 중 어떤 토큰을 얼마나 참고할 것인지 계산하는 과정이다.
  - "The cat was tired because it ..."에서 "it"을 처리할 때 앞의 "cat"과의 관계를 계산한다.
- Query : 현재 토큰이 어떤 정보를 찾고 있는지를 표현한 벡터이다.
  - 현재 토큰 → Q
- Key : 각 토큰이 어떤 정보를 가지고 있는지를 비교하기 위한 벡터.
  - 이전 Token → K
- Value : 어텐션 계산 후 실제로 가져와서 사용할 정보를 담고 있는 벡터이다.
 - Q와 K 비교 → 중요도 계산 → 해당 중요도로 V를 조합
- Head : Attention을 하나의 큰 계산으로 수행하지 않고 여러 개의 작은 어텐션으로 나눠서 병렬로 처리하는 단위이다. 일반적으로 Attention Head라고 부른다.
  - Head 1, Head 2, Head 3 ... 각각 Attention을 계산한 뒤 결과를 합친다.
- Multi-Head Attention : 여러 개의 Attention Head를 동시에 사용해서 토큰 간의 관계를 여러 관점에서 계산하는 방식이다.
  - Input → Head 1 / Head 2 / Head 3 / ... → 결과 합치기 → Linear Projection 
- Head Dimension : 하나의 Attention Head가 사용하는 벡터의 크기이다. 예를 들어 hidden_size=896, num_attention_heads=14라면 하나의 Head는 보통 64차원을 사용한다.
  - 896 / 14 = 64
- MHA : Multi-Head Attention의 기본 형태이다. Query Head 수와 Key/Value Head 수가 동일하다. 
  - Q Head=16, K Head=16, V Head=16
- FFN : Attention 계산 이후 각 토큰의 벡터 자체를 추가로 변환하는 신경망이다. Attention이 토큰 간의 관계를 계산한다면 FFN은 각 토큰의 표현을 더 복잡하게 변환한다고 볼 수 있다.
  - 896 → 4864 → Activation → 896
- KV Cache : 이전 Token에서 이미 계산한 Key와 Value를 GPU 메모리에 저장해두는 공간이다. 다음 토큰을 생성할 때 이전 토큰의 K/V를 다시 계산하지 않기 위해 사용한다.
  - Token 1~100의 K/V 저장 → Token 101 생성 시 재사용
- Prefill : 사용자가 입력한 Prompt 전체를 처음 한 번에 계산하는 단계이다. 이 과정에서 입력된 모든 토큰에 대해 Attention 계산을 수행하고 K/V 값을 만들어 KV Cache에 저장한다.
  - Prompt 100 Token → Transformer 계산 → KV Cache 생성
- Decode : Prefill 이후 새로운 토큰 하나씩 생성하는 단계이다. 새로운 토큰이 생성될 때마다 해당 Token의 K/V만 추가로 계산해서 KV Cache에 저장한다.
  - Token 101 생성 → KV Cache 추가 → Token 102 생성 → KV Cache 추가
- PagedAttention : vLLM에서 KV Cache를 고정된 연속 메모리로 관리하지 않고 작은 Block 단위로 나눠서 관리하는 방식이다. 메모리 낭비를 줄이고 여러 요청의 KV Cache를 효율적으로 관리하기 위해 사용한다.
  - KV Cache → Block 1 / Block 2 / Block 3 / ...
- lock Size : PagedAttention에서 하나의 KV Cache Block에 몇 개의 토큰을 저장할지를 의미한다. 
  - block_size=16 → 하나의 Block이 16 Token 단위로 관리됨
- Chunked Prefill : 긴 Prompt의 Prefill을 한 번에 처리하지 않고 여러 Chunk로 나눠서 처리하는 방식이다. 긴 Prefill 요청 하나가 Decode 요청들을 오래 막는 것을 줄일 수 있다.
  - Prompt 8000 Token → 2000 + 2000 + 2000 + 2000

## 1. 실행 환경과 GPU 초기화(T4 ver.2026.04)

GPU garbage collection를 위한 함수 정의
```python
import gc
import torch

def free_gpu():
    gc.collect()

    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        torch.cuda.ipc_collect()
        torch.cuda.reset_peak_memory_stats()

    print("GPU cache cleared")
```

특정 버전의 vLLM 다운로드
```bash
# 약 2분 소요, 이후 세션 재시작 필요
%pip install -q -U uv
!uv pip install --system "vllm==0.17.0" --torch-backend=auto

# 결과
Using Python 3.12.13 environment at: /usr
Resolved 183 packages in 3.18s
Prepared 36 packages in 1m 30s
Uninstalled 18 packages in 2.03s
Installed 36 packages in 670ms
```

## 2. vLLM을 활용한 추론 테스트

첫 실행은 하나의 긴 프롬프트를 생성해 vLLM 로드와 생성 흐름이 정상인지 확인한다. 이 단계에서 보는 값 다음과 같다. 
- 모델 로드 시간
- 생성 시간
- 생성 토큰 수

```python
# 약 4분 소요
import time
from vllm import LLM, SamplingParams

model_name = "Qwen/Qwen2.5-0.5B"

# Load model with vLLM.
llm = LLM(model=model_name, dtype="float16")

# Define the prompt.
prompt = """You are an expert AI historian writing a detailed chapter for a book titled "The Evolution of Human-AI Collaboration."

Begin by summarizing the early stages of artificial intelligence in the 1950s, touching on symbolic logic and rule-based systems. Then transition into the rise of machine learning, particularly deep learning in the 2010s.

Afterward, describe how large language models like GPT transformed human-computer interaction, enabling applications in education, creative writing, customer support, and software development.

Finally, reflect on the societal and ethical implications of AI, such as misinformation, bias, and the alignment problem.

Write in a formal tone, with rich detail and examples in each era."""

# Create sampling parameters.
sampling_params = SamplingParams(temperature=0.8, top_p=0.95, max_tokens=128)

# Time the model generation.
start_time = time.time()
outputs = llm.generate([prompt], sampling_params)
end_time = time.time()

# Print the results.
for output in outputs:
  print(f"Generated text: {output}")
  print(f"Time taken: {end_time - start_time:.2f} seconds")


# results
/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/chat_completion/protocol.py:346: SyntaxWarning: invalid escape sequence '\e'
  "(e.g. 'abcdabcdabcd...' or '\emoji \emoji \emoji ...'). This feature "
  
/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/completion/protocol.py:176: SyntaxWarning: invalid escape sequence '\e'
  "(e.g. 'abcdabcdabcd...' or '\emoji \emoji \emoji ...'). This feature "
  
INFO 08-07 06:34:58 [utils.py:238] non-default args: {'dtype': 'float16', 'disable_log_stats': True, 'model': 'Qwen/Qwen2.5-0.5B'}

/usr/local/lib/python3.12/dist-packages/huggingface_hub/utils/_auth.py:94: UserWarning: 
The secret `HF_TOKEN` does not exist in your Colab secrets.

To authenticate with the Hugging Face Hub, create a token in your settings tab (https://huggingface.co/settings/tokens), set it as secret in your Google Colab and restart your session.

You will be able to reuse this secret in all of your notebooks.
Please note that authentication is recommended but still optional to access public models or datasets.

  warnings.warn(
config.json: 100%
 681/681 [00:00<00:00, 75.7kB/s]
INFO 08-07 06:35:24 [model.py:531] Resolved architecture: Qwen2ForCausalLM
WARNING 08-07 06:35:24 [model.py:1892] Casting torch.bfloat16 to torch.float16.
INFO 08-07 06:35:24 [model.py:1554] Using max model len 32768
INFO 08-07 06:35:25 [scheduler.py:231] Chunked prefill is enabled with max_num_batched_tokens=8192.
INFO 08-07 06:35:25 [vllm.py:747] Asynchronous scheduling is enabled.

tokenizer_config.json: 
 7.23k/? [00:00<00:00, 615kB/s]
vocab.json: 
 2.78M/? [00:00<00:00, 60.7MB/s]
merges.txt: 
 1.67M/? [00:00<00:00, 47.0MB/s]
tokenizer.json: 
 7.03M/? [00:00<00:00, 115MB/s]
generation_config.json: 100%
 138/138 [00:00<00:00, 13.9kB/s]

WARNING 08-07 06:35:28 [system_utils.py:152] We must use the `spawn` multiprocessing start method. Overriding VLLM_WORKER_MULTIPROC_METHOD to 'spawn'. See https://docs.vllm.ai/en/latest/usage/troubleshooting.html#python-multiprocessing for more information. Reasons: CUDA is initialized

INFO 08-07 06:39:36 [llm.py:388] Supported tasks: ['generate']
Rendering prompts: 100%
 1/1 [00:00<00:00, 12.04it/s]
Processed prompts: 100%
 1/1 [00:01<00:00,  1.08s/it, est. speed input: 131.82 toks/s, output: 118.82 toks/s]

# prompot 생략
Generated text: RequestOutput(request_id=0, prompt='', prompt_token_ids=[2610, 525, 458, 6203, 15235, 42968, 4378, 264, 11682, 12453, 369, 264, 2311, 24849, 330, 785, 37221, 315, 11097, 6691, 40, 86587, 2217, 11135, 553, 28285, 4849, 279, 4124, 17628, 315, 20443, 11229, 304, 279, 220, 16, 24, 20, 15, 82, 11, 30587, 389, 35296, 12218, 323, 5912, 5980, 5942, 13, 5005, 9142, 1119, 279, 10000, 315, 5662, 6832, 11, 7945, 5538, 6832, 304, 279, 220, 17, 15, 16, 15, 82, 382, 6025, 1606, 11, 7512, 1246, 3460, 4128, 4119, 1075, 479, 2828, 23507, 3738, 11476, 11281, 16230, 11, 27362, 8357, 304, 6731, 11, 11521, 4378, 11, 6002, 1824, 11, 323, 3162, 4401, 382, 23949, 11, 8708, 389, 279, 58429, 323, 30208, 24154, 315, 15235, 11, 1741, 438, 74059, 11, 15470, 11, 323, 279, 17189, 3491, 382, 7985, 304, 264, 15908, 16232, 11, 448, 9080, 7716, 323, 10295, 304, 1817, 11385, 13], encoder_prompt=None, encoder_prompt_token_ids=None, prompt_logprobs=None, outputs=[CompletionOutput(index=0, text=" ", token_ids=[34006, 79912, 11, 502, 70821, 11, 323, 6351, 4128, 13, 4230, 264, 5530, 315, 13656, 2266, 311, 16579, 12726, 323, 10306, 77825, 304, 697, 19221, 13, 10869, 25, 576, 37221, 315, 11097, 6691, 40, 86587, 271, 785, 4124, 17628, 315, 20443, 11229, 320, 15469, 8, 304, 279, 220, 16, 24, 20, 15, 82, 1033, 12864, 553, 279, 4401, 315, 35296, 12218, 323, 5912, 5980, 5942, 13, 758, 279, 220, 16, 24, 21, 15, 82, 11, 1493, 14310, 1033, 11577, 553, 279, 9688, 315, 20443, 29728, 14155, 11, 892, 1033, 14606, 553, 279, 8109, 594, 23759, 7321, 382, 15090, 292, 12218, 323, 5912, 5980, 5942, 1033, 279, 16266, 315, 15235, 3412, 304, 279, 220, 16, 24, 20, 15, 82, 13, 4220, 5942, 1033, 1483, 311, 4009, 12624, 323, 5601], routed_experts=None, cumulative_logprob=None, logprobs=None, finish_reason=length, stop_reason=None)], finished=True, metrics=None, lora_request=None, num_cached_tokens=0)

Time taken: 1.17 seconds
```

pytorch allocator가 잡고 있지만 사용하지 않는 cache 반환
```python
if "llm" in globals():
    del llm

free_gpu()
```

gpu 자원 사용량 확인 
```bash
!nvidia-smi
```

## 3. 기본 설정과 배치 설정 비교
다음 조건으로 실행을 진행했다.  
- 동일한 모델 Qwen2.5-0.5B
- 동일한 프롬프트와 생성 조건을 사용
- 동시 요청 수를 1 / 32 / 64 / 128

비교 지표는 다음과 같아. 이를 통해 튜닝이 단일 요청 지연시간과 다중 요청 처리량에 어떤 영향을 주는지 확인했다.  
- 요청 처리 시간
- Requests/sec
- Output tokens/sec

튜닝 설정에는 관련 옵션 등이 포함되어 있으며, 동시 요청이 증가할 때 vLLM의 스케줄링과 KV Cache 관리 최적화가 처리량 향상에 얼마나 기여하는지 확인하는 것이 실험의 주요 목적이다.  
- max_model_len
- gpu_memory_utilization
- max_num_seqs
- Prefix Caching
- Chunked Prefill
- CUDA Graph 

공통 코드 설정 
```python
import gc
import time
import torch

from vllm import LLM, SamplingParams


model_name = "Qwen/Qwen2.5-0.5B"

sampling_params = SamplingParams(
    temperature=0.8,
    top_p=0.95,
    max_tokens=128,
    seed=42,
)

prompt = """You are an expert AI historian writing a detailed chapter for a book titled "The Evolution of Human-AI Collaboration."

Begin by summarizing the early stages of artificial intelligence in the 1950s, touching on symbolic logic and rule-based systems. Then transition into the rise of machine learning, particularly deep learning in the 2010s.

Afterward, describe how large language models like GPT transformed human-computer interaction, enabling applications in education, creative writing, customer support, and software development.

Finally, reflect on the societal and ethical implications of AI, such as misinformation, bias, and the alignment problem.

Write in a formal tone, with rich detail and examples in each era."""

def benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=1,
    warmup=True,
    repeat=5,
):
    prompts = [prompt] * num_requests

    # 동일 concurrency로 Warm-up
    if warmup:
        llm.generate(
            prompts,
            sampling_params,
            use_tqdm=False,
        )

        torch.cuda.synchronize()

    times = []
    token_rates = []
    outputs_last = None

    # 여러 번 반복 측정
    for _ in range(repeat):

        torch.cuda.synchronize()

        start = time.perf_counter()

        outputs = llm.generate(
            prompts,
            sampling_params,
            use_tqdm=False,
        )

        torch.cuda.synchronize()

        elapsed = time.perf_counter() - start

        output_tokens = sum(
            len(output.outputs[0].token_ids)
            for output in outputs
        )

        times.append(elapsed)
        token_rates.append(
            output_tokens / elapsed
        )

        outputs_last = outputs

    torch.cuda.synchronize()

    elapsed = time.perf_counter() - start

    # Token 수 계산
    input_tokens = sum(
        len(output.prompt_token_ids)
        for output in outputs
    )

    output_tokens = sum(
        len(output.outputs[0].token_ids)
        for output in outputs
    )

    peak_memory = (
        torch.cuda.max_memory_allocated() / 1024**3
    )

    return {
        "requests": num_requests,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "time_sec": elapsed,
        "requests_per_sec": num_requests / elapsed,
        "output_tokens_per_sec": output_tokens / elapsed,
        "total_tokens_per_sec":
            (input_tokens + output_tokens) / elapsed,
        "peak_gpu_memory_gb": peak_memory,
    }


def print_result(name, result):
    print(f"\n========== {name} ==========")
    print(f"Requests           : {result['requests']}")
    print(f"Input tokens       : {result['input_tokens']}")
    print(f"Output tokens      : {result['output_tokens']}")
    print(f"Time               : {result['time_sec']:.3f} sec")
    print(f"Requests/sec       : {result['requests_per_sec']:.2f}")
    print(f"Output tokens/sec  : {result['output_tokens_per_sec']:.2f}")
    print(f"Total tokens/sec   : {result['total_tokens_per_sec']:.2f}")
    print(f"Peak GPU memory    : {result['peak_gpu_memory_gb']:.2f} GB")
```

### 3.1 기본 설정
```python
load_start = time.perf_counter()

llm = LLM(
    model=model_name,
    dtype="float16",
)

baseline_load_time = time.perf_counter() - load_start

print(f"Baseline load time: {baseline_load_time:.2f} sec")
============================
Baseline load time: 41.31 sec
```

단일 요청
```python
baseline_1 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=1,
    repeat=5,
)

print_result(
    "Baseline - Single",
    baseline_1
)

========== Baseline - Single ==========
Requests           : 1
Input tokens       : 142
Output tokens      : 128
Time               : 1.031 sec
Requests/sec       : 0.97
Output tokens/sec  : 124.19
Total tokens/sec   : 261.95
Peak GPU memory    : 0.00 GB

```

32개 다중 요청
```python
baseline_32 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=32,
    repeat=5,
)

print_result(
    "Baseline - Batch 32",
    baseline_32
)

========== Baseline - Batch 32 ==========
Requests           : 32
Input tokens       : 4544
Output tokens      : 4096
Time               : 1.295 sec
Requests/sec       : 24.72
Output tokens/sec  : 3164.08
Total tokens/sec   : 6674.22
Peak GPU memory    : 0.00 GB
```

64개 다중 요청
```python
baseline_64 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=64,
    repeat=5,
)

print_result(
    "Baseline - Batch 64",
    baseline_64
)


========== Baseline - Batch 64 ==========
Requests           : 64
Input tokens       : 9088
Output tokens      : 8192
Time               : 1.781 sec
Requests/sec       : 35.94
Output tokens/sec  : 4599.78
Total tokens/sec   : 9702.65
Peak GPU memory    : 0.00 GB
```

128개 다중 요청
```python
baseline_128 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=128,
    repeat=5,
)

print_result(
    "Baseline - Batch 128",
    baseline_128
)

========== Baseline - Batch 128 ==========
Requests           : 128
Input tokens       : 18176
Output tokens      : 16384
Time               : 2.906 sec
Requests/sec       : 44.04
Output tokens/sec  : 5637.02
Total tokens/sec   : 11890.60
Peak GPU memory    : 0.00 GB
```

pytorch allocator가 잡고 있지만 사용하지 않는 cache 반환
```python
if "llm" in globals():
    del llm

free_gpu()
```

### 3.2 튜닝 설정

```python
# 튜닝 모델 로드
load_start = time.perf_counter()

llm = LLM(
    model=model_name,
    dtype="float16",

    # Memory / context
    swap_space=4,
    max_model_len=4096,
    gpu_memory_utilization=0.90,

    # PagedAttention / KV Cache
    block_size=16,
    enable_prefix_caching=True,

    # Scheduler
    max_num_seqs=256,

    # Prefill
    enable_chunked_prefill=True,

    # CUDA Graph
    enforce_eager=False,

    # Multi-GPU
    disable_custom_all_reduce=False,
)

tuned_load_time = time.perf_counter() - load_start

print(f"Tuned load time: {tuned_load_time:.2f} sec")

=======================
Tuned load time: 41.84 sec
```

단일 요청
```python
tuned_1 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=1,
    repeat=5,
)

print_result(
    "Tuned - Single",
    tuned_1
)

========== Tuned - Single ==========
Requests           : 1
Input tokens       : 142
Output tokens      : 128
Time               : 0.887 sec
Requests/sec       : 1.13
Output tokens/sec  : 144.38
Total tokens/sec   : 304.56
Peak GPU memory    : 0.00 GB
```

32개 다중 요청
```python
tuned_32 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=32,
    repeat=5,
)

print_result(
    "Tuned - Batch 32",
    tuned_32
)

========== Tuned - Batch 32 ==========
Requests           : 32
Input tokens       : 4544
Output tokens      : 4096
Time               : 1.389 sec
Requests/sec       : 23.03
Output tokens/sec  : 2948.16
Total tokens/sec   : 6218.78
Peak GPU memory    : 0.00 GB
```

64개 다중 요청
```python
tuned_64 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=64,
    repeat=5,
)

print_result(
    "Tuned - Batch 64",
    tuned_64
)

========== Tuned - Batch 64 ==========
Requests           : 64
Input tokens       : 9088
Output tokens      : 8192
Time               : 1.764 sec
Requests/sec       : 36.28
Output tokens/sec  : 4643.76
Total tokens/sec   : 9795.42
Peak GPU memory    : 0.00 GB
```

128개 다중 요청
```python
tuned_128 = benchmark_llm(
    llm,
    prompt,
    sampling_params,
    num_requests=128,
    repeat=5,
)

print_result(
    "Tuned - Batch 128",
    tuned_128
)

========== Tuned - Batch 128 ==========
Requests           : 128
Input tokens       : 18176
Output tokens      : 16384
Time               : 2.625 sec
Requests/sec       : 48.77
Output tokens/sec  : 6242.11
Total tokens/sec   : 13166.96
Peak GPU memory    : 0.00 GB

```

pytorch allocator가 잡고 있지만 사용하지 않는 cache 반환
```python
if "llm" in globals():
    del llm

free_gpu()
```

## 4. 결과 비교
```python
def percent_change(old, new):
    return ((new - old) / old) * 100


def latency_improvement(old, new):
    return ((old - new) / old) * 100

# Result

print("\n" + "=" * 65)
print("                 BASELINE vs TUNED")
print("=" * 65)


print("\n[Model Loading]")
print(f"Baseline : {baseline_load_time:.2f} sec")
print(f"Tuned    : {tuned_load_time:.2f} sec")

print(
    f"Change   : "
    f"{latency_improvement(baseline_load_time, tuned_load_time):+.2f}%"
)


print("\n[Single Request]")

print(
    f"Latency       : "
    f"{baseline_1['time_sec']:.3f} -> "
    f"{tuned_1['time_sec']:.3f} sec"
)

print(
    f"Latency Δ     : "
    f"{latency_improvement(
        baseline_1['time_sec'],
        tuned_1['time_sec']
    ):+.2f}%"
)

print(
    f"Output tok/s  : "
    f"{baseline_1['output_tokens_per_sec']:.2f} -> "
    f"{tuned_1['output_tokens_per_sec']:.2f}"
)

print(
    f"Throughput Δ  : "
    f"{percent_change(
        baseline_1['output_tokens_per_sec'],
        tuned_1['output_tokens_per_sec']
    ):+.2f}%"
)


print("\n[Batch 32]")

print(
    f"Time          : "
    f"{baseline_32['time_sec']:.3f} -> "
    f"{tuned_32['time_sec']:.3f} sec"
)

print(
    f"Requests/sec  : "
    f"{baseline_32['requests_per_sec']:.2f} -> "
    f"{tuned_32['requests_per_sec']:.2f}"
)

print(
    f"Output tok/s  : "
    f"{baseline_32['output_tokens_per_sec']:.2f} -> "
    f"{tuned_32['output_tokens_per_sec']:.2f}"
)

print(
    f"Throughput Δ  : "
    f"{percent_change(
        baseline_32['output_tokens_per_sec'],
        tuned_batch32['output_tokens_per_sec']
    ):+.2f}%"
)

print("\n[Batch 64]")

print(
    f"Time          : "
    f"{baseline_64['time_sec']:.3f} -> "
    f"{tuned_64['time_sec']:.3f} sec"
)

print(
    f"Requests/sec  : "
    f"{baseline_64['requests_per_sec']:.2f} -> "
    f"{tuned_64['requests_per_sec']:.2f}"
)

print(
    f"Output tok/s  : "
    f"{baseline_64['output_tokens_per_sec']:.2f} -> "
    f"{tuned_64['output_tokens_per_sec']:.2f}"
)

print(
    f"Throughput Δ  : "
    f"{percent_change(
        baseline_64['output_tokens_per_sec'],
        tuned_64['output_tokens_per_sec']
    ):+.2f}%"
)

print("\n[Batch 128]")

print(
    f"Time          : "
    f"{baseline_128['time_sec']:.3f} -> "
    f"{tuned_128['time_sec']:.3f} sec"
)

print(
    f"Requests/sec  : "
    f"{baseline_128['requests_per_sec']:.2f} -> "
    f"{tuned_128['requests_per_sec']:.2f}"
)

print(
    f"Output tok/s  : "
    f"{baseline_128['output_tokens_per_sec']:.2f} -> "
    f"{tuned_128['output_tokens_per_sec']:.2f}"
)

print(
    f"Throughput Δ  : "
    f"{percent_change(
        baseline_128['output_tokens_per_sec'],
        tuned_128['output_tokens_per_sec']
    ):+.2f}%"
)

=================================================================
                 BASELINE vs TUNED
=================================================================

[Model Loading]
Baseline : 39.80 sec
Tuned    : 39.88 sec
Change   : -0.19%

[Single Request]
Latency       : 1.031 -> 0.887 sec
Latency Δ     : +13.99%
Output tok/s  : 124.19 -> 144.38
Throughput Δ  : +16.26%

[Batch 32]
Time          : 1.295 -> 1.389 sec
Requests/sec  : 24.72 -> 23.03
Output tok/s  : 3164.08 -> 2948.16
Throughput Δ  : -5.62%

[Batch 64]
Time          : 1.781 -> 1.764 sec
Requests/sec  : 35.94 -> 36.28
Output tok/s  : 4599.78 -> 4643.76
Throughput Δ  : +0.96%

[Batch 128]
Time          : 2.906 -> 2.625 sec
Requests/sec  : 44.04 -> 48.77
Output tok/s  : 5637.02 -> 6242.11
Throughput Δ  : +10.73%
```

## 5. 분석
튜닝 설정은 모델 로딩에는 영향을 거의 주지 않았고, 단일 요청에서는 약 16%, 높은 concurrency 128에서는 약 11%의 처리량 개선을 보였다. 
하지만 concurrency 32~64에서는 효과가 없거나 소폭 손해가 있어, workload별 최적값 탐색이 필요하다.

```sh
Output tok/s

6500 |                         T ●
6000 |                         B ●
5500 |
5000 |
4500 |              B● T●
4000 |
3500 |
3000 |       B●
     |       T●
2500 |
     +------------------------------
        1      32    64      128
```


Ref
- https://github.com/orca3/llm-model-inference/blob/main/ch02/ch2_Run_LLM_With_vLLM.ipynb