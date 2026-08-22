## [LLM Serving 스터디 3주차](https://learn.kodekloud.com/learn/courses/youtube-labs-vllm)

> Kodecloud의 vllm 실습을 통해 운영 환경에서 왜 vLLM이 적합한지를 정리한 내용입니다.

HuggingFace와 vLLM을 비교하며 KV Cache, PagedAttention, Continuous Batching의 원리를 이해하고, 실제 운영 환경에서 고성능 LLM 서빙을 위한 성능 최적화을 실습한다.

## 목차

| Task  | Script                     | TODOs | Key Skill                            |
| ----- | -------------------------- | ----- | ------------------------------------ |
| Setup | verify_environment.py      | 0     | 모델 환경 설정                          |
| 1     | task_1_hf_baseline.py      | 2     | 기본 LLM 추론 방식 이해                   |
| 2     | task_2_vllm_inference.py   | 2     | vLLM 과 HuggingFace 비교               |
| 3     | task_3_kv_cache_problem.py | 2     | KV cache에 대한 이해                    |
| 4     | task_4_paged_attention.py  | 3     | PagedAttention 효과                   |
| 5     | task_5_api_server.py       | 2     | OpenAI 호환 API                        |
| 6     | task_6_multi_user_load.py  | 2     | 동시 사용자 로드 테스트                    |
| 7     | task_7_tuning.py           | 2     | 프러덕션급 최적화                         |
| 8     | task_8_dashboard.py        | 3     | web 시각화   정리                       |

### 0. 실행 환경 세팅 

- 파이썬 가상 환경 및 패키지 설치 (vllm, transformers, gradio, aiohttp)
- 모델 : SmolLM-135M 다운로드 

<details>
<summary> 전체 코드 </summary>

```python
#!/usr/bin/env python3
"""
Setup: Verify Environment
Checks the lab environment and downloads the SmolLM-135M model.
"""

import os
import sys
import time


def verify_environment():
    """Verify all lab prerequisites are met."""
    print("=" * 65)
    print("vLLM Explained Lab - Environment Verification")
    print("=" * 65)

    checks_passed = 0
    checks_total = 5

    # Check 1: Virtual environment
    print("\n[1/5] Checking Python virtual environment...")
    if os.path.exists("/root/venv"):
        print("  PASS - Virtual environment found at /root/venv")
        checks_passed += 1
    else:
        print("  FAIL - Virtual environment not found")
        print("  Fix: Run 'python3 -m venv /root/venv && source /root/venv/bin/activate'")
        return False

    # Check 2: Required packages
    print("\n[2/5] Checking required packages...")
    try:
        import torch
        import transformers
        print(f"  PASS - torch {torch.__version__}")
        print(f"  PASS - transformers {transformers.__version__}")
        checks_passed += 1
    except ImportError as e:
        print(f"  FAIL - Missing package: {e}")
        print("  Fix: Run 'pip install torch transformers'")
        return False

    # Check 3: vLLM (must be the CPU build)
    print("\n[3/5] Checking vLLM installation...")
    try:
        import vllm
        # Check the package metadata version, not vllm.__version__ -
        # the runtime __version__ strips the +cpu suffix ("0.24.0"),
        # while the metadata keeps it ("0.24.0+cpu"). vLLM's platform
        # detection reads the metadata version too.
        from importlib.metadata import version as pkg_version
        vllm_version = pkg_version("vllm")
        if "cpu" in vllm_version:
            print(f"  PASS - vllm {vllm_version} (CPU build)")
            checks_passed += 1
        else:
            print(f"  FAIL - vllm {vllm_version} is not the CPU build")
            print("  The generic PyPI wheel is a CUDA build and cannot run")
            print("  on this GPU-less machine (fails with 'Device string must")
            print("  not be empty' at engine init).")
            print("  Fix: Reinstall the CPU wheel:")
            print("    pip uninstall -y vllm")
            print("    pip install 'https://github.com/vllm-project/vllm/releases/download/v0.24.0/vllm-0.24.0+cpu-cp38-abi3-manylinux_2_34_x86_64.whl' --extra-index-url https://download.pytorch.org/whl/cpu")
            return False
    except ImportError as e:
        print(f"  FAIL - vLLM not installed: {e}")
        print("  Fix: Re-run the lab startup script or contact support")
        return False

    # Check 4: Additional packages
    print("\n[4/5] Checking additional packages...")
    try:
        import gradio
        import aiohttp
        import requests
        print(f"  PASS - gradio {gradio.__version__}")
        print(f"  PASS - aiohttp {aiohttp.__version__}")
        print(f"  PASS - requests {requests.__version__}")
        checks_passed += 1
    except ImportError as e:
        print(f"  FAIL - Missing package: {e}")
        print("  Fix: Run 'pip install gradio aiohttp requests'")
        return False

    # Check 5: Download SmolLM-135M model
    print("\n[5/5] Downloading SmolLM-135M model...")
    print("  This may take a minute on first run...")
    try:
        from transformers import AutoModelForCausalLM, AutoTokenizer

        model_name = "HuggingFaceTB/SmolLM-135M"
        start_time = time.time()

        print(f"  Downloading tokenizer for {model_name}...")
        tokenizer = AutoTokenizer.from_pretrained(model_name)

        print(f"  Downloading model for {model_name}...")
        model = AutoModelForCausalLM.from_pretrained(model_name)

        elapsed = time.time() - start_time
        param_count = sum(p.numel() for p in model.parameters()) / 1e6

        print(f"  PASS - Model downloaded in {elapsed:.1f}s")
        print(f"  Model size: {param_count:.0f}M parameters")

        # Quick test generation
        print("\n  Running quick test generation...")
        inputs = tokenizer("Hello, world!", return_tensors="pt")
        outputs = model.generate(**inputs, max_new_tokens=10)
        test_output = tokenizer.decode(outputs[0], skip_special_tokens=True)
        print(f"  Test output: {test_output[:80]}...")
        print("  PASS - Model generates text successfully")

        # Clean up memory
        del model
        del tokenizer

        checks_passed += 1
    except Exception as e:
        print(f"  FAIL - Model download failed: {e}")
        return False

    # Summary
    print("\n" + "=" * 65)
    print(f"ENVIRONMENT CHECK: {checks_passed}/{checks_total} passed")
    print("=" * 65)

    if checks_passed == checks_total:
        print("\nAll checks passed! Your environment is ready.")
        print("\nLab Scenario:")
        print("  You are an ML engineer at InferenceIO.")
        print("  Mission: Use vLLM to serve SmolLM to concurrent users.")
        print("\nNext step: Run Task 1")
        print("  python /root/code/task_1_hf_baseline.py")

        # Create marker
        os.makedirs("/root/markers", exist_ok=True)
        with open("/root/markers/environment_verified.txt", "w") as f:
            f.write("ENVIRONMENT_VERIFIED\n")

        print("\nEnvironment verification complete!")
        return True
    else:
        print(f"\n{checks_total - checks_passed} check(s) failed. Fix the issues above and retry.")
        return False


if __name__ == "__main__":
    success = verify_environment()
    sys.exit(0 if success else 1)
```
</details>

### 0.1 결과

총 5가지 검증을 진행한다.

1. 가상환경 존재 여부 확인
2. 필요 패키지 설치 여부 확인
   1. torch == 2.11.0+cpu
   2. transformers == 5.15.0
3. vLLM 설치 여부 확인
   1. vllm == 0.24.0+cpu (CPU build)
4. 추가 패키지 설치 여부 확인
   1. gradio
   2. aiohttp 
   3. requests
5. SmolLM-135M 모델 다운로드 및 테스트 생성

```sh
python verify_environment.py 

=================================================================
vLLM Explained Lab - Environment Verification
=================================================================

[1/5] Checking Python virtual environment...
  PASS - Virtual environment found at /root/venv

[2/5] Checking required packages...
  PASS - torch 2.11.0+cpu
  PASS - transformers 5.15.0

[3/5] Checking vLLM installation...
  PASS - vllm 0.24.0+cpu (CPU build)

[4/5] Checking additional packages...
  PASS - gradio 5.50.0
  PASS - aiohttp 3.14.3
  PASS - requests 2.34.2

[5/5] Downloading SmolLM-135M model...
  This may take a minute on first run...
  Downloading tokenizer for HuggingFaceTB/SmolLM-135M...
Warning: You are sending unauthenticated requests to the HF Hub. Please set a HF_TOKEN to enable higher rate limits and faster downloads.
config.json: 100%|█| 724/724 [00:00<00:00, 6.53
tokenizer_config.json: 100%|█| 3.69k/3.69k [00:
vocab.json: 100%|█| 801k/801k [00:00<00:00, 110
merges.txt: 100%|█| 466k/466k [00:00<00:00, 108
special_tokens_map.json: 100%|█| 831/831 [00:00
tokenizer.json: 100%|█| 2.10M/2.10M [00:00<00:0
  Downloading model for HuggingFaceTB/SmolLM-135M...
model.safetensors: downloading bytes: █|  238MB
model.safetensors: reconstructing file: 100%|█|
Loading weights: 100%|█| 272/272 [00:00<00:00, 
generation_config.json: 100%|█| 111/111 [00:00<
  PASS - Model downloaded in 7.5s
  Model size: 135M parameters

  Running quick test generation...
  Test output: Hello, world!

**Step 1: Understanding What a...
  PASS - Model generates text successfully

=================================================================
ENVIRONMENT CHECK: 5/5 passed
=================================================================

All checks passed! Your environment is ready.

Lab Scenario:
  You are an ML engineer at InferenceIO.
  Mission: Use vLLM to serve SmolLM to concurrent users.

Next step: Run Task 1
  python /root/code/task_1_hf_baseline.py

Environment verification complete!
```

### 1. task_1_hf_baseline.py

- SmolLM-135M 모델을 허깅페이스의 AutoModelForCausalLM 활용하여 읽어들인다
- 50개의 토큰 생성하여 초당 생성시간 측정 
- 결과 저장 `/root/markers/hf_baseline.txt`

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 1: Naive HuggingFace Inference - The Baseline
Measure baseline inference speed using raw HuggingFace transformers.
"""

import os
import time


def main():
    print("=" * 65)
    print("Task 1: Naive HuggingFace Inference - The Baseline")
    print("=" * 65)

    from transformers import AutoModelForCausalLM, AutoTokenizer

    model_name = "HuggingFaceTB/SmolLM-135M"
    prompt = "Explain what a large language model is in simple terms."

    print(f"\nModel: {model_name}")
    print(f"Prompt: \"{prompt}\"")
    print("-" * 65)

    # --- LOAD MODEL ---
    print("\nLoading model with HuggingFace transformers...")

    # TODO 1: Load the model
    # Hint: Use the model_name variable ("HuggingFaceTB/SmolLM-135M")
    model = AutoModelForCausalLM.from_pretrained(model_name)  # TODO: Set to model_name

    tokenizer = AutoTokenizer.from_pretrained(model_name)

    # Set pad token if not set
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    print("Model loaded successfully.")

    # --- GENERATE ---
    print("\nGenerating with HuggingFace transformers...")
    inputs = tokenizer(prompt, return_tensors="pt")

    # TODO 2: Set the max_new_tokens for generation
    # Hint: Controls how many tokens the model generates
    start_time = time.time()
    outputs = model.generate(
        **inputs,
        max_new_tokens=50,  # TODO: Set to 50
        do_sample=True,
        temperature=0.7,
    )
    end_time = time.time()

    # Calculate metrics
    input_tokens = inputs["input_ids"].shape[1]
    total_tokens = outputs.shape[1]
    generated_tokens = total_tokens - input_tokens
    total_time = end_time - start_time
    tokens_per_second = generated_tokens / total_time

    # Decode output
    output_text = tokenizer.decode(outputs[0], skip_special_tokens=True)

    # --- RESULTS ---
    print("\n--- RESULTS ---")
    print(f"Generated text: {output_text[:200]}...")
    print(f"\nGenerated tokens: {generated_tokens}")
    print(f"Total time: {total_time:.2f} seconds")
    print(f"Tokens per second: {tokens_per_second:.1f} tok/s")

    # Save baseline for later comparison
    baseline_file = "/root/markers/hf_baseline.txt"
    os.makedirs("/root/markers", exist_ok=True)
    with open(baseline_file, "w") as f:
        f.write(f"tokens_per_second={tokens_per_second:.2f}\n")
        f.write(f"total_time={total_time:.4f}\n")
        f.write(f"generated_tokens={generated_tokens}\n")

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- This is SINGLE-REQUEST performance")
    print("- There is no batching - one request at a time")
    print("- Under load with multiple users, requests would queue up")
    print("- Next: See how vLLM improves this (Task 2)")
    print("=" * 65)

    # Create marker file
    with open("/root/markers/task1_complete.txt", "w") as f:
        f.write("TASK_1_COMPLETE\n")

    print("\nTask 1 Complete!")
    print("Next: python /root/code/task_2_vllm_inference.py")

    # Clean up
    del model
    del tokenizer


if __name__ == "__main__":
    main()
```
</details>

<details>
<summary> 핵심 코드 요약 </summary>

```python
from transformers import AutoModelForCausalLM, AutoTokenizer

# 모델 이름 지정
model_name = "HuggingFaceTB/SmolLM-135M"

# 토크나이저 로드 
tokenizer = AutoTokenizer.from_pretrained(model_name)

# 모델 로드 
model = AutoModelForCausalLM.from_pretrained(model_name)

# 프롬프트 정의
prompt = "Explain what a large language model is in simple terms."

# 프롬프트를 토큰 ID 텐서로 변환 (PyTorch 텐서 형식으로 TensorFlow, NumPy, JAX 등도 가능)
inputs = tokenizer(prompt, return_tensors="pt")

# 텍스트 생성
outputs = model.generate(
    **inputs,          # 토큰 주입
    max_new_tokens=50, # 최대 토큰 수 
    do_sample=True,    # 샘플링 방식 사용 (greedy 대신 확률적 선택)
    temperature=0.7,   # 샘플링 다양성 조절 (낮을수록 결정적), 0이상의 값을 갖는다. 낮을수록 다음 단어가 가장 높은 확률의 토큰이 선택된다. 1.0 이상으로 높다면 창의적인 생성 가능성이 높아진다. 말도 안되는 값 생성 가능. 0.7은 적절한 다양성을 제공한다.
)

# 전체 메트릭 추출
# 입력 토큰 및 생성된 토큰 수 계산, 토큰 생성 시간 추출, 토큰당 생성 속도 계산
input_tokens = inputs["input_ids"].shape[1]
total_tokens = outputs.shape[1]
generated_tokens = total_tokens - input_tokens
total_time = end_time - start_time
tokens_per_second = generated_tokens / total_time

# 생성된 토큰을 다시 텍스트로 변환 (특수 토큰 제외)
output_text = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(output_text)
print(f"생성 토큰 수: {generated_tokens}, 소요 시간: {total_time:.2f}s, 속도: {tokens_per_second:.2f} tokens/sec")
```
</details>


### 1.1 결과

50개의 토큰 생성에 대해서 총 5.21s가 소요되었으며, 이는 초당 9.6 토큰을 생성할수 있음을 의미한다. 

```sh
python task_1_hf_baseline.py 
=================================================================
Task 1: Naive HuggingFace Inference - The Baseline
=================================================================

Model: HuggingFaceTB/SmolLM-135M
Prompt: "Explain what a large language model is in simple terms."
-----------------------------------------------------------------

Loading model with HuggingFace transformers...
Warning: You are sending unauthenticated requests to the HF Hub. Please set a HF_TOKEN to enable higher rate limits and faster downloads.
Loading weights: 100%|█| 272/272 [00:00<00:00, 
Model loaded successfully.

Generating with HuggingFace transformers...

--- RESULTS ---
Generated text: Explain what a large language model is in simple terms.

A large language model is a type of artificial intelligence that is trained to generate text based on the input it is given. It can be thought ...

Generated tokens: 50
Total time: 5.21 seconds
Tokens per second: 9.6 tok/s

=================================================================
KEY INSIGHT:
- This is SINGLE-REQUEST performance
- There is no batching - one request at a time
- Under load with multiple users, requests would queue up
- Next: See how vLLM improves this (Task 2)
=================================================================

Task 1 Complete!
Next: python /root/code/task_2_vllm_inference.py
```

### 2. task_2_vllm_inference.py

- vLLM를 활용하려 모델 로드 
- 허깅페이스와 vLLM을 비교한다. 
- 결과 저장 `/root/markers/vllm_baseline.txt`

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 2: vLLM Offline Inference - See the Difference
Compare vLLM inference speed against the HuggingFace baseline.
"""

import os
import time

# Configure vLLM for CPU-only execution.
# The lab VM has a 4GB memory limit, so run the engine in-process
# (VLLM_ENABLE_V1_MULTIPROCESSING=0): the default multi-process mode
# spawns 2 extra Python processes that each cost over 1GB.
# VLLM_CPU_KVCACHE_SPACE is deliberately unset - it would override the
# kv_cache_memory_bytes argument and only accepts whole GiB values.
os.environ["VLLM_TARGET_DEVICE"] = "cpu"
os.environ["VLLM_ENABLE_V1_MULTIPROCESSING"] = "0"
os.environ.pop("VLLM_CPU_KVCACHE_SPACE", None)
os.environ["TORCHDYNAMO_DISABLE"] = "1"

# 128MB KV cache - holds ~43 full-length sequences for SmolLM-135M at
# max_model_len=128 (~22.5KB KV per token). Kept small because vLLM's
# startup check counts the pod's page cache (model downloads) as used
# memory, leaving only a few hundred MB "available" on the 4GB VM.
KV_CACHE_BYTES = 128 * 1024 * 1024


def main():
    print("=" * 65)
    print("Task 2: vLLM Offline Inference - See the Difference")
    print("=" * 65)

    from vllm import LLM, SamplingParams

    model_name = "HuggingFaceTB/SmolLM-135M"
    prompt = "Explain what a large language model is in simple terms."

    print(f"\nModel: {model_name}")
    print(f"Prompt: \"{prompt}\"")
    print("-" * 65)

    # --- INITIALIZE vLLM ---
    print("\nInitializing vLLM engine...")

    # TODO 1: Initialize the vLLM engine
    # Hint: Pass the model_name variable to the LLM constructor
    # Note: enforce_eager=True skips torch.compile to save memory on CPU
    llm = LLM(model=model_name, max_model_len=128, enforce_eager=True,
              kv_cache_memory_bytes=KV_CACHE_BYTES)  # TODO: Set to model_name

    # TODO 2: Create SamplingParams for generation
    # Hint: Set temperature and max_tokens for text generation
    sampling_params = SamplingParams(temperature=0.7, max_tokens=50)  # TODO: Set to 0.7 and 50

    print("vLLM engine ready.")

    # --- GENERATE ---
    print("\nGenerating with vLLM...")
    start_time = time.time()
    outputs = llm.generate([prompt], sampling_params)
    end_time = time.time()

    # Extract results
    generated_text = outputs[0].outputs[0].text
    generated_tokens = len(outputs[0].outputs[0].token_ids)
    total_time = end_time - start_time
    tokens_per_second = generated_tokens / total_time

    # --- vLLM RESULTS ---
    print("\n--- vLLM RESULTS ---")
    print(f"Generated text: {generated_text[:200]}...")
    print(f"\nGenerated tokens: {generated_tokens}")
    print(f"Total time: {total_time:.2f} seconds")
    print(f"Tokens per second: {tokens_per_second:.1f} tok/s")

    # --- COMPARISON ---
    print("\n--- COMPARISON: HuggingFace vs vLLM ---")
    hf_tps = None
    hf_time = None
    baseline_file = "/root/markers/hf_baseline.txt"
    if os.path.exists(baseline_file):
        with open(baseline_file, "r") as f:
            for line in f:
                key, value = line.strip().split("=")
                if key == "tokens_per_second":
                    hf_tps = float(value)
                elif key == "total_time":
                    hf_time = float(value)

    if hf_tps:
        print(f"{'Metric':<20} {'HuggingFace':>12} {'vLLM':>12}")
        print("-" * 46)
        print(f"{'Tokens/sec':<20} {hf_tps:>12.1f} {tokens_per_second:>12.1f}")
        print(f"{'Total time':<20} {hf_time:>11.2f}s {total_time:>11.2f}s")
        if tokens_per_second > hf_tps:
            speedup = tokens_per_second / hf_tps
            print(f"\nvLLM is {speedup:.1f}x faster in tokens/sec")
        else:
            print("\nNote: For single requests, results may be similar.")
            print("The real advantage shows under concurrent load (Task 6).")
    else:
        print("(HuggingFace baseline not found - run Task 1 first)")

    # Save vLLM metrics for later comparison
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/vllm_baseline.txt", "w") as f:
        f.write(f"tokens_per_second={tokens_per_second:.2f}\n")
        f.write(f"total_time={total_time:.4f}\n")
        f.write(f"generated_tokens={generated_tokens}\n")

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- vLLM optimizes inference even for single requests")
    print("- The REAL advantage is under concurrent load (Task 6)")
    print("- vLLM handles batching natively - no manual queue management")
    print("- Before that, let's understand WHY vLLM is faster (Tasks 3-4)")
    print("=" * 65)

    # Create marker
    with open("/root/markers/task2_complete.txt", "w") as f:
        f.write("TASK_2_COMPLETE\n")

    print("\nTask 2 Complete!")
    print("Next: python /root/code/task_3_kv_cache_problem.py")

    # Clean up
    del llm


if __name__ == "__main__":
    main()
```

</details>

<details>
<summary> 핵심 요약</summary>

동일한 프롬프트 50개의 토큰 생성에 대해서 허깅페이스와 vLLM 비교한 결과는 명확하다. vLLM은 수동으로 별도의 최적화 없이도 허깅 페이스 대비 초당 토큰 생성량이 1.3배 빠르다 

**그렇다면 KV 캐시 값을 계산하느 식은??**

```sh
Metric                HuggingFace         vLLM
----------------------------------------------
Tokens/sec                    9.6         12.8
Total time                  5.21s        3.90s
```


```python

# vLLM을 CPU 전용으로 실행하도록 환경변수 설정
# 실습 VM은 4GB 메모리 제한이 있어서, 엔진을 in-process로 실행
# (VLLM_ENABLE_V1_MULTIPROCESSING=0): 기본 멀티프로세스 모드는
# 별도 파이썬 프로세스 2개를 띄우는데 각각 1GB 이상 소모됨
# VLLM_CPU_KVCACHE_SPACE는 일부러 설정 안 함 - kv_cache_memory_bytes
# 인자와 충돌하고, GiB 단위 정수 값만 받기 때문
os.environ["VLLM_TARGET_DEVICE"] = "cpu"          # 실행 디바이스를 CPU로 강제 지정
os.environ["VLLM_ENABLE_V1_MULTIPROCESSING"] = "0"  # 멀티프로세싱 비활성화 (메모리 절약)
os.environ.pop("VLLM_CPU_KVCACHE_SPACE", None)      # 혹시 설정돼 있으면 제거 (충돌 방지)
os.environ["TORCHDYNAMO_DISABLE"] = "1"             # torch dynamo 비활성화 (CPU에서 불필요/불안정)

# 128MB KV 캐시 - SmolLM-135M, max_model_len=128 기준
# 토큰당 KV 약 22.5KB이므로 약 43개 시퀀스 분량을 담을 수 있음
# 작게 잡은 이유: vLLM의 시작 시 메모리 체크가 모델 다운로드로 생긴
# 페이지 캐시까지 "사용 중"으로 잡아서, 4GB VM에서 "가용" 메모리가
# 몇백 MB밖에 안 남기 때문
KV_CACHE_BYTES = 128 * 1024 * 1024

from vllm import LLM, SamplingParams

# vLLM 엔진 초기화
llm = LLM(
    model=model_name,              # 사용할 모델
    max_model_len=128,             # 최대 시퀀스 길이 제한 (메모리 절약)
    enforce_eager=True,            # torch.compile 생략 (CPU 메모리 절약)
    kv_cache_memory_bytes=KV_CACHE_BYTES,  # KV 캐시 크기 명시적 지정
)

# 샘플링 파라미터 설정 (HF baseline과 동일 조건으로 비교하기 위함)
sampling_params = SamplingParams(
    temperature=0.7,   # 생성 다양성 조절
    max_tokens=50,     # 최대 생성 토큰 수
)

# 시간 측정
start_time = time.time()
outputs = llm.generate([prompt], sampling_params)  # 프롬프트 리스트를 넣으면 배치 생성 가능
end_time = time.time()

# 결과 추출
generated_text = outputs[0].outputs[0].text                 # 생성된 텍스트
generated_tokens = len(outputs[0].outputs[0].token_ids)     # 생성된 토큰 수
total_time = end_time - start_time                          # 소요 시간
tokens_per_second = generated_tokens / total_time            # 처리 속도
```
</details>



### 2.1 결과

```sh
python task_2_vllm_inference.py 
=================================================================
Task 2: vLLM Offline Inference - See the Difference
=================================================================
INFO 08-18 22:12:54 [importing.py:46] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-18 22:12:54 [importing.py:58] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-18 22:12:54 [importing.py:81] Triton not installed or not compatible; certain GPU-related functions will not be available.

Model: HuggingFaceTB/SmolLM-135M
Prompt: "Explain what a large language model is in simple terms."
-----------------------------------------------------------------

Initializing vLLM engine...
INFO 08-18 22:12:56 [api_utils.py:273] non-default args: {'max_model_len': 128, 'kv_cache_memory_bytes': 134217728, 'disable_log_stats': True, 'enforce_eager': True, 'model': 'HuggingFaceTB/SmolLM-135M'}
Warning: You are sending unauthenticated requests to the HF Hub. Please set a HF_TOKEN to enable higher rate limits and faster downloads.
WARNING 08-18 22:12:56 [arg_utils.py:1590] The global random seed is set to 0. Since VLLM_ENABLE_V1_MULTIPROCESSING is set to False, this may affect the random state of the Python process that launched vLLM.
INFO 08-18 22:13:02 [model.py:598] Resolved architecture: LlamaForCausalLM
INFO 08-18 22:13:02 [model.py:1725] Using max model len 128
INFO 08-18 22:13:02 [scheduler.py:252] Chunked prefill is enabled with max_num_batched_tokens=4096.
INFO 08-18 22:13:02 [vllm.py:1006] Asynchronous scheduling is enabled.
WARNING 08-18 22:13:02 [vllm.py:1062] Enforce eager set, disabling torch.compile and CUDAGraphs. This is equivalent to setting -cc.mode=none -cc.cudagraph_mode=none
WARNING 08-18 22:13:02 [vllm.py:1110] Inductor compilation was disabled by user settings, optimizations settings that are only active during inductor compilation will be ignored.
INFO 08-18 22:13:02 [kernel.py:276] Final IR op priority after setting platform defaults: IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native'])
WARNING 08-18 22:13:02 [vllm.py:534] Model Runner V2 requires Triton; using the V1 model runner instead.
INFO 08-18 22:13:02 [compilation.py:310] Enabled custom fusions: norm_quant, act_quant
INFO 08-18 22:13:04 [core.py:114] Initializing a V1 LLM engine (v0.24.0) with config: model='HuggingFaceTB/SmolLM-135M', speculative_config=None, tokenizer='HuggingFaceTB/SmolLM-135M', skip_tokenizer_init=False, tokenizer_mode=auto, revision=None, tokenizer_revision=None, trust_remote_code=False, dtype=torch.bfloat16, max_seq_len=128, download_dir=None, load_format=auto, tensor_parallel_size=1, pipeline_parallel_size=1, data_parallel_size=1, decode_context_parallel_size=1, dcp_comm_backend=ag_rs, disable_custom_all_reduce=True, quantization=None, quantization_config=None, enforce_eager=True, enable_return_routed_experts=False, kv_cache_dtype=auto, device_config=cpu, structured_outputs_config=StructuredOutputsConfig(backend='auto', disable_any_whitespace=False, disable_additional_properties=False, reasoning_parser='', reasoning_parser_plugin='', enable_in_reasoning=False), observability_config=ObservabilityConfig(show_hidden_metrics_for_version=None, otlp_traces_endpoint=None, collect_detailed_traces=None, kv_cache_metrics=False, kv_cache_metrics_sample=0.01, cudagraph_metrics=False, enable_layerwise_nvtx_tracing=False, enable_mfu_metrics=False, enable_mm_processor_stats=False, enable_logging_iteration_details=False, jit_monitor_verbose=False), seed=0, served_model_name=HuggingFaceTB/SmolLM-135M, enable_prefix_caching=True, enable_chunked_prefill=True, pooler_config=None, compilation_config={'mode': <CompilationMode.NONE: 0>, 'debug_dump_path': None, 'cache_dir': '', 'compile_cache_save_format': 'binary', 'backend': 'inductor', 'custom_ops': ['all'], 'ir_enable_torch_wrap': False, 'splitting_ops': [], 'compile_mm_encoder': False, 'cudagraph_mm_encoder': False, 'encoder_cudagraph_token_budgets': [], 'encoder_cudagraph_max_vision_items_per_batch': 0, 'encoder_cudagraph_max_frames_per_batch': None, 'compile_sizes': None, 'compile_ranges_endpoints': [4096], 'inductor_compile_config': {'enable_auto_functionalized_v2': False, 'size_asserts': False, 'alignment_asserts': False, 'scalar_asserts': False}, 'inductor_passes': {}, 'cudagraph_mode': <CUDAGraphMode.NONE: 0>, 'cudagraph_num_of_warmups': 0, 'cudagraph_capture_sizes': [], 'cudagraph_copy_inputs': False, 'cudagraph_specialize_lora': True, 'use_inductor_graph_partition': False, 'pass_config': {'fuse_norm_quant': True, 'fuse_act_quant': True, 'fuse_attn_quant': False, 'enable_sp': False, 'fuse_gemm_comms': False, 'fuse_allreduce_rms': False, 'fuse_rope_kvcache_cat_mla': False, 'fuse_act_padding': False}, 'max_cudagraph_capture_size': None, 'dynamic_shapes_config': {'type': <DynamicShapesType.BACKED: 'backed'>, 'evaluate_guards': False, 'assume_32_bit_indexing': False}, 'local_cache_dir': None, 'fast_moe_cold_start': False, 'static_all_moe_layers': []}, kernel_config=KernelConfig(ir_op_priority=IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native']), enable_flashinfer_autotune=True, moe_backend='auto', linear_backend='auto')
[W818 22:13:04.597042626 utils.cpp:68] Warning: NUMA binding: Using MEMBIND policy for memory allocation on the NUMA nodes (0). Memory allocations will be strictly bound to these NUMA nodes. (function init_cpu_memory_env)
WARNING 08-18 22:13:04 [cpu_worker.py:114] libiomp is not found in LD_PRELOAD. For best performance, please follow the section `set LD_PRELOAD` in https://docs.vllm.ai/en/latest/getting_started/installation/cpu/ to setup required pre-loaded libraries.
INFO 08-18 22:13:04 [parallel_state.py:1588] world_size=1 rank=0 local_rank=0 distributed_init_method=tcp://10.244.37.12:49431 backend=gloo
INFO 08-18 22:13:04 [parallel_state.py:1923] rank 0 in world size 1 is assigned as DP rank 0, PP rank 0, PCP rank 0, TP rank 0, EP rank N/A, EPLB rank N/A
INFO 08-18 22:13:04 [cpu_model_runner.py:113] Starting to load model HuggingFaceTB/SmolLM-135M...
INFO 08-18 22:13:04 [selector.py:138] Using HND KV cache layout for CPU_ATTN backend.
INFO 08-18 22:13:05 [weight_utils.py:574] No model.safetensors.index.json found in remote.
INFO 08-18 22:13:05 [weight_utils.py:849] Filesystem type for checkpoints: OVERLAY. Checkpoint size: 0.50 GiB. Available RAM: 48.59 GiB.
INFO 08-18 22:13:05 [weight_utils.py:872] Auto-prefetch is disabled because the filesystem (OVERLAY) is not a recognized network FS (NFS/Lustre). If you want to force prefetching, start vLLM with --safetensors-load-strategy=prefetch.
Loading safetensors checkpoint shards: 100% Com
INFO 08-18 22:13:05 [default_loader.py:430] Loading weights took 0.34 seconds
INFO 08-18 22:13:05 [cpu_model_runner.py:130] Warming up model for the compilation...
INFO 08-18 22:13:12 [cpu_model_runner.py:134] Warming up done.
INFO 08-18 22:13:12 [cpu_worker.py:235] Explicitly set (0.12/3.73) GiB for KV cache on node 0.
INFO 08-18 22:13:12 [kv_cache_utils.py:2146] GPU KV cache size: 5,760 tokens
INFO 08-18 22:13:12 [kv_cache_utils.py:2147] Maximum concurrency for 128 tokens per request: 45.00x
INFO 08-18 22:13:12 [core.py:344] init engine (profile, create kv cache, warmup model) took 7.13 s
vLLM engine ready.

Generating with vLLM...
Rendering prompts: 100%|█| 1/1 [00:00<00:00, 10
Processed prompts: 100%|█| 1/1 [00:03<00:00,  3

--- vLLM RESULTS ---
Generated text:  An LLM is a computer program that can process large amounts of data in a short period of time. It can be used to generate text, analyze data, and even predict future events.

Let's take a look at a s...

Generated tokens: 50
Total time: 3.90 seconds
Tokens per second: 12.8 tok/s

--- COMPARISON: HuggingFace vs vLLM ---
Metric                HuggingFace         vLLM
----------------------------------------------
Tokens/sec                    9.6         12.8
Total time                  5.21s        3.90s

vLLM is 1.3x faster in tokens/sec

=================================================================
KEY INSIGHT:
- vLLM optimizes inference even for single requests
- The REAL advantage is under concurrent load (Task 6)
- vLLM handles batching natively - no manual queue management
- Before that, let's understand WHY vLLM is faster (Tasks 3-4)
=================================================================

Task 2 Complete!
Next: python /root/code/task_3_kv_cache_problem.py
```

### 3. task_3_kv_cache_problem.py

- 서로 다른 길이의 5개의 동시 요청에 대한 테스트 
- 사용되지 않은 gpu 측정 (~80%)

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 3: The KV Cache Problem - Why Memory Matters
Simulate KV cache fragmentation with contiguous memory allocation.
"""

import os


def main():
    print("=" * 65)
    print("Task 3: The KV Cache Problem - Why Memory Matters")
    print("=" * 65)

    # Simulated requests with different prompt lengths
    requests = [
        {"id": 1, "prompt_tokens": 45,  "description": "Short question"},
        {"id": 2, "prompt_tokens": 128, "description": "Medium paragraph"},
        {"id": 3, "prompt_tokens": 23,  "description": "Quick greeting"},
        {"id": 4, "prompt_tokens": 256, "description": "Long document"},
        {"id": 5, "prompt_tokens": 67,  "description": "Code snippet"},
    ]

    # TODO 1: Set the maximum sequence length for worst-case allocation
    # Hint: Traditional systems use values like 512, 2048, or 4096
    max_seq_len = 512  # TODO: Set to 512

    print(f"\nMax sequence length (pre-allocated per request): {max_seq_len}")
    print(f"Number of concurrent requests: {len(requests)}")

    # --- SIMULATE CONTIGUOUS ALLOCATION ---
    print("\n--- SIMULATING CONTIGUOUS ALLOCATION ---")
    print(f"(Each request gets {max_seq_len} token slots, regardless of actual usage)\n")

    total_allocated = 0
    total_used = 0

    for req in requests:
        actual = req["prompt_tokens"]
        allocated = max_seq_len
        total_allocated += allocated
        total_used += actual

        # Create visual bar
        bar_width = 50
        used_chars = int((actual / allocated) * bar_width)
        wasted_chars = bar_width - used_chars
        bar = "#" * used_chars + "." * wasted_chars

        # TODO 2: Calculate the wasted memory percentage
        # Hint: Subtract actual from allocated, then divide by allocated
        wasted_pct = (allocated - actual) / allocated * 100  # TODO: Set to (allocated - actual) / allocated * 100

        print(f"  Request {req['id']} ({req['description']}):")
        print(f"    [{bar}] {actual}/{allocated} used ({wasted_pct:.1f}% wasted)")

    # --- SUMMARY ---
    overall_utilization = total_used / total_allocated * 100
    overall_waste = 100 - overall_utilization

    print(f"\n--- SUMMARY ---")
    print(f"Total allocated: {total_allocated} token slots")
    print(f"Total actually used: {total_used} token slots")
    print(f"Memory utilization: {overall_utilization:.1f}%")
    print(f"Overall waste: {overall_waste:.1f}%")

    # Visual comparison
    print(f"\n--- WHY THIS IS A PROBLEM ---")
    print(f"  With {max_seq_len}-token pre-allocation:")
    print(f"  - You allocated {total_allocated} slots but only used {total_used}")
    print(f"  - {overall_waste:.1f}% of your memory is WASTED")
    print(f"  - That wasted memory could serve MORE users")
    if overall_waste > 60:
        print(f"  - This matches vLLM's finding: 60-80% memory waste in traditional systems")

    # Max users comparison
    hypothetical_memory = 10000  # Assume 10000 token slots of total memory
    max_users_contiguous = hypothetical_memory // max_seq_len
    avg_actual = total_used // len(requests)
    max_users_ideal = hypothetical_memory // avg_actual

    print(f"\n--- CONCURRENT USER IMPACT ---")
    print(f"  With {hypothetical_memory} total memory slots:")
    print(f"  - Contiguous allocation: {max_users_contiguous} concurrent users max")
    print(f"  - Ideal (no waste): {max_users_ideal} concurrent users max")
    print(f"  - You are serving {max_users_contiguous}x fewer users than possible!")

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- Traditional systems pre-allocate WORST-CASE memory per request")
    print("- Short prompts waste massive amounts of memory")
    print("- This limits how many concurrent requests you can serve")
    print("- This is the EXACT problem vLLM's PagedAttention solves (Task 4)")
    print("=" * 65)

    # Create marker
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/task3_complete.txt", "w") as f:
        f.write("TASK_3_COMPLETE\n")

    print("\nTask 3 Complete!")
    print("Next: python /root/code/task_4_paged_attention.py")


if __name__ == "__main__":
    main()
```

</details>

<details>
<summary> 핵심 요약</summary>

각 요청마다 실제 길이와 상관없이 최대 길이 max_seq_len를 할당한다. wasted_pct와 overall_waste를 계산한 뒤, 이 낭비로 인해 동시에 서비스할수 있는 사용자가 얼마나 줄어드는지 계산한다. 실습을 통해 gpu를 서빙하기 위해서 gpu 최적화는 선택이 아님 필수임을 알수가 있다. 다음 챕터에서 vLLM의 PagedAttention이 이러한 문제를 해결한다 

```python
requests = [
    {"id": 1, "prompt_tokens": 45,  "description": "Short question"},
    {"id": 2, "prompt_tokens": 128, "description": "Medium paragraph"},
    {"id": 3, "prompt_tokens": 23,  "description": "Quick greeting"},
    {"id": 4, "prompt_tokens": 256, "description": "Long document"},
    {"id": 5, "prompt_tokens": 67,  "description": "Code snippet"},
]

# 전통적인 서빙 시스템은 요청이 실제로 몇 토큰을 쓰든 상관없이
# "최악의 경우(worst-case)"를 가정해서 미리 고정된 크기의 메모리를 할당한다.
# 즉, 512 / 2048 / 4096 같은 값 하나를 정해두고
# 모든 요청에 그만큼의 슬롯을 무조건 예약해버림 (실제 사용량과 무관하게)
max_seq_len = 512  

# 전체 요청들이 "할당받은" 토큰 슬롯 총합 (항상 max_seq_len만큼씩 더해짐)
total_allocated = 0

# 전체 요청들이 "실제로 사용한" 토큰 수 총합 (prompt_tokens 실제값)
total_used = 0

for req in requests:
    # 이 요청이 실제로 사용한 토큰 수

    actual = req["prompt_tokens"]
        # 이 요청에 할당된 토큰 수는 실제 길이와 무관하게 항상 max_seq_len 고정

    allocated = max_seq_len
    total_allocated += allocated
    total_used += actual

    # 막대 전체 길이(문자 수)
    bar_width = 50

    # 할당량 대비 실제 사용 비율만큼을 '#'(사용됨)로 표시
    used_chars = int((actual / allocated) * bar_width)

    # 나머지는 '.'(낭비된 부분)로 표시
    wasted_chars = bar_width - used_chars
    bar = "#" * used_chars + "." * wasted_chars

    # 이 요청에서 할당량 대비 실제로 낭비된 메모리 비율(%)
    # (할당량 - 실제 사용량) / 할당량 * 100
    wasted_pct = (allocated - actual) / allocated * 100  

    print(f"  Request {req['id']} ({req['description']}):")
    print(f"    [{bar}] {actual}/{allocated} used ({wasted_pct:.1f}% wasted)")

# --- SUMMARY ---
# 전체 요청 기준 "실제 메모리 활용률" = 총 사용량 / 총 할당량

overall_utilization = total_used / total_allocated * 100
# 전체 낭비율 = 100%에서 활용률을 뺀 값

overall_waste = 100 - overall_utilization

# 가상의 총 메모리 용량을 10000 토큰 슬롯이라고 가정하고
# "고정 할당 방식"과 "이상적인(낭비 없는) 방식"의 최대 동시 처리 가능 사용자 수를 비교
hypothetical_memory = 10000  # Assume 10000 token slots of total memory
# 고정 할당 방식: 요청마다 무조건 max_seq_len만큼 잡아먹으므로
# 전체 메모리를 max_seq_len으로 나눈 값이 최대 동시 사용자 수
max_users_contiguous = hypothetical_memory // max_seq_len
# 요청들의 평균 실제 사용 토큰 수
avg_actual = total_used // len(requests)
# 이상적인 방식: 실제 평균 사용량만큼만 할당한다고 가정했을 때의 최대 동시 사용자 수
max_users_ideal = hypothetical_memory // avg_actual
```

</details>


### 3.1 결과
```sh
python task_3_kv_cache_problem.py 
=================================================================
Task 3: The KV Cache Problem - Why Memory Matters
=================================================================

Max sequence length (pre-allocated per request): 512
Number of concurrent requests: 5

--- SIMULATING CONTIGUOUS ALLOCATION ---
(Each request gets 512 token slots, regardless of actual usage)

  Request 1 (Short question):
    [####..............................................] 45/512 used (91.2% wasted)
  Request 2 (Medium paragraph):
    [############......................................] 128/512 used (75.0% wasted)
  Request 3 (Quick greeting):
    [##................................................] 23/512 used (95.5% wasted)
  Request 4 (Long document):
    [#########################.........................] 256/512 used (50.0% wasted)
  Request 5 (Code snippet):
    [######............................................] 67/512 used (86.9% wasted)

--- SUMMARY ---
Total allocated: 2560 token slots
Total actually used: 519 token slots
Memory utilization: 20.3%
Overall waste: 79.7%

--- WHY THIS IS A PROBLEM ---
  With 512-token pre-allocation:
  - You allocated 2560 slots but only used 519
  - 79.7% of your memory is WASTED
  - That wasted memory could serve MORE users
  - This matches vLLM's finding: 60-80% memory waste in traditional systems

--- CONCURRENT USER IMPACT ---
  With 10000 total memory slots:
  - Contiguous allocation: 19 concurrent users max
  - Ideal (no waste): 97 concurrent users max
  - You are serving 19x fewer users than possible!

=================================================================
KEY INSIGHT:
- Traditional systems pre-allocate WORST-CASE memory per request
- Short prompts waste massive amounts of memory
- This limits how many concurrent requests you can serve
- This is the EXACT problem vLLM's PagedAttention solves (Task 4)
=================================================================

Task 3 Complete!
Next: python /root/code/task_4_paged_attention.py
```



### 4. [task_4_paged_attention.py](https://youtu.be/c-VZNLfZ93c?si=jQXs3XE-9E23pwTJ)

- paged_attention 적용에 대한 성능 향상 비교
- 사용량 향상 출력 약 ~95%

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 4: PagedAttention - vLLM's Solution
Compare paged allocation vs contiguous allocation for KV cache.
"""

import os
import math


def main():
    print("=" * 65)
    print("Task 4: PagedAttention - vLLM's Solution")
    print("=" * 65)

    # Same requests from Task 3
    requests = [
        {"id": 1, "prompt_tokens": 45,  "description": "Short question"},
        {"id": 2, "prompt_tokens": 128, "description": "Medium paragraph"},
        {"id": 3, "prompt_tokens": 23,  "description": "Quick greeting"},
        {"id": 4, "prompt_tokens": 256, "description": "Long document"},
        {"id": 5, "prompt_tokens": 67,  "description": "Code snippet"},
    ]

    max_seq_len = 512  # From Task 3

    # TODO 1: Set the page size for paged allocation
    # Hint: A typical page holds 16 tokens (like OS 4KB pages)
    page_size = 16  # TODO: Set to 16

    print(f"\nPage size: {page_size} tokens per page")
    print(f"Contiguous allocation: {max_seq_len} tokens per request (worst-case)")

    # --- PAGED ALLOCATION ---
    print("\n--- PAGED ALLOCATION (like vLLM's PagedAttention) ---\n")

    total_paged_allocated = 0
    total_contiguous_allocated = 0
    total_used = 0

    for req in requests:
        actual = req["prompt_tokens"]
        total_used += actual

        # Contiguous: worst-case allocation
        contiguous_alloc = max_seq_len
        total_contiguous_allocated += contiguous_alloc

        # TODO 2: Calculate how many pages are needed
        # Hint: Round up to nearest page using math.ceil
        pages_needed = math.ceil(actual / page_size)  # TODO: Set to page_size

        paged_alloc = pages_needed * page_size
        total_paged_allocated += paged_alloc

        paged_waste = (paged_alloc - actual) / paged_alloc * 100 if paged_alloc > 0 else 0

        # Visual: show pages
        page_blocks = "|".join(["##" if i < pages_needed else ".." for i in range(pages_needed)])

        print(f"  Request {req['id']}: {actual} tokens -> {pages_needed} pages ({paged_alloc} slots)")
        print(f"    Pages: [{page_blocks}]  waste: {paged_waste:.1f}%")

    # TODO 3: Calculate paged memory utilization
    # Hint: Divide total used by total paged allocated
    paged_utilization = total_used / total_paged_allocated * 100  # TODO: Set to total_paged_allocated
    contiguous_utilization = total_used / total_contiguous_allocated * 100

    # --- SIDE-BY-SIDE COMPARISON ---
    print(f"\n--- SIDE-BY-SIDE COMPARISON ---")
    print(f"{'Method':<14} {'Total Allocated':>16} {'Total Used':>12} {'Utilization':>13}")
    print("-" * 57)
    print(f"{'Contiguous':<14} {total_contiguous_allocated:>12} slots {total_used:>8} slots {contiguous_utilization:>12.1f}%")
    print(f"{'Paged':<14} {total_paged_allocated:>12} slots {total_used:>8} slots {paged_utilization:>12.1f}%")

    memory_saved = total_contiguous_allocated - total_paged_allocated
    savings_ratio = total_contiguous_allocated / total_paged_allocated if total_paged_allocated > 0 else 0

    print(f"\nMemory saved: {memory_saved} slots ({savings_ratio:.1f}x less memory)")

    # --- CONCURRENT USER IMPACT ---
    hypothetical_memory = 10000
    max_users_contiguous = hypothetical_memory // max_seq_len
    avg_paged = total_paged_allocated // len(requests)
    max_users_paged = hypothetical_memory // avg_paged if avg_paged > 0 else 0

    print(f"\n--- CONCURRENT USER IMPACT ---")
    print(f"  With {hypothetical_memory} total memory slots:")
    print(f"  - Contiguous: {max_users_contiguous} concurrent users")
    print(f"  - Paged:      {max_users_paged} concurrent users")
    print(f"  - Improvement: {max_users_paged / max_users_contiguous:.1f}x more users!")

    # --- OS PAGING ANALOGY ---
    print(f"\n--- OS PAGING ANALOGY ---")
    print(f"  Contiguous = reserving an entire row of seats for each person")
    print(f"  Paged      = giving seats one at a time as people sit down")
    print(f"")
    print(f"  Just like OS virtual memory:")
    print(f"  - OS divides RAM into fixed-size pages (typically 4KB)")
    print(f"  - Processes get pages on demand, not large contiguous blocks")
    print(f"  - vLLM does the same for KV cache during LLM inference")

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- PagedAttention uses small pages (like OS virtual memory)")
    print("- No worst-case pre-allocation needed")
    print(f"- Memory utilization: {contiguous_utilization:.0f}% -> {paged_utilization:.0f}%")
    print("- This frees memory to serve MORE concurrent users")
    print("- Next: Let's use this in practice with vLLM's API server (Task 5)")
    print("=" * 65)

    # Create marker
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/task4_complete.txt", "w") as f:
        f.write("TASK_4_COMPLETE\n")

    print("\nTask 4 Complete!")
    print("Next: python /root/code/task_5_api_server.py")


if __name__ == "__main__":
    main()
```
</details>

<details>
<summary> 핵심 요약</summary> 

Paged attention을 사용했을 때와 안한 경우에 대한 결과 비교이다. Slot은 KV cache에서 토큰 1개를 저장할수 있는 공간이다. Contiguous Allocation는 각 사용자마다 하나의 공간 전체를 부여한다. slot 256이라고 정의하면 이를 전부 예약한다. slot을 전부 사용하던 사용하지 않던, 반면 Paged Attention는 필요한만큼의 slot을 할당한다. 자신이 할당받은 slot을 초과하면 이를 추가로 할당하는 방식으로, 즉 필요할때마다 Block을 추가로 할당한다.

결과적으로 KV cache 사용량은 4.7배 감소하고, contiguous Allocation 대비 약 4.8배의 더 많은 동시 사용자를 수용할수가 있다.

```sh
Method          Total Allocated   Total Used   Utilization
---------------------------------------------------------
Contiguous             2560 slots      519 slots         20.3%
Paged                   544 slots      519 slots         95.4%

Memory saved: 2016 slots (4.7x less memory)

--- CONCURRENT USER IMPACT ---
  With 10000 total memory slots:
  - Contiguous: 19 concurrent users
  - Paged:      92 concurrent users
  - Improvement: 4.8x more users!
```

```python
requests = [
    {"id": 1, "prompt_tokens": 45,  "description": "Short question"},
    {"id": 2, "prompt_tokens": 128, "description": "Medium paragraph"},
    {"id": 3, "prompt_tokens": 23,  "description": "Quick greeting"},
    {"id": 4, "prompt_tokens": 256, "description": "Long document"},
    {"id": 5, "prompt_tokens": 67,  "description": "Code snippet"},
]

# Task 3의 max_seq_len(512) - "기존 방식"의 최대 할당량, 비교 기준용
max_seq_len = 512  # From Task 3

# vLLM PagedAttention의 핵심: 메모리를 작은 "페이지" 단위로 쪼갠다.
# OS가 RAM을 보통 4KB 페이지로 나누는 것처럼, 여기서는 토큰 16개를 한 페이지로 정의
page_size = 16  # TODO: Set to 16

total_paged_allocated = 0       # 페이징 방식으로 실제 할당된 총 슬롯 수
total_contiguous_allocated = 0  # 기존(연속 할당) 방식의 총 슬롯 수 (비교용)
total_used = 0                  # 요청들이 실제로 사용한 토큰 수 총합

for req in requests:
    actual = req["prompt_tokens"]
    total_used += actual

    # 기존 방식: 실제 길이와 무관하게 항상 max_seq_len(512)을 통째로 예약
    contiguous_alloc = max_seq_len
    total_contiguous_allocated += contiguous_alloc

    # 페이징 방식: 실제 토큰 수를 page_size(16)로 나눠서 필요한 페이지 수 계산.
    # 딱 나누어떨어지지 않으면 올림(ceil) 처리해서 페이지 하나를 더 배정
    # (예: 45토큰 -> 45/16 = 2.8125 -> ceil -> 3페이지)
    pages_needed = math.ceil(actual / page_size)  # TODO: Set to page_size 

    # 실제 할당 슬롯 수는 "필요한 페이지 수 x 페이지 크기"
    # (512를 통째로 잡는 게 아니라, 필요한 만큼만 페이지 단위로 확보)
    paged_alloc = pages_needed * page_size
    total_paged_allocated += paged_alloc

    # 페이징 방식도 마지막 페이지는 완전히 안 채워질 수 있어 약간의 낭비는 남음
    # (다만 512 전체를 잡는 것보다는 훨씬 적음)
    paged_waste = (paged_alloc - actual) / paged_alloc * 100 if paged_alloc > 0 else 0

    # 페이지 개수를 시각적으로 보여주는 블록
    page_blocks = "|".join(["##" if i < pages_needed else ".." for i in range(pages_needed)])

    print(f"  Request {req['id']}: {actual} tokens -> {pages_needed} pages ({paged_alloc} slots)")
    print(f"    Pages: [{page_blocks}]  waste: {paged_waste:.1f}%")

# 페이징 방식의 전체 메모리 활용률 = 실제 사용량 / 페이징 방식 총 할당량
paged_utilization = total_used / total_paged_allocated * 100  # TODO: Set to total_paged_allocated
# 기존 방식의 전체 메모리 활용률 = 실제 사용량 / 기존 방식 총 할당량
contiguous_utilization = total_used / total_contiguous_allocated * 100

# 페이징 방식으로 절약된 메모리 슬롯 수, 몇 배나 덜 쓰는지(효율)
memory_saved = total_contiguous_allocated - total_paged_allocated
savings_ratio = total_contiguous_allocated / total_paged_allocated if total_paged_allocated > 0 else 0

# 절약된 메모리가 "동시 처리 가능한 사용자 수"에 얼마나 영향을 주는지 비교
hypothetical_memory = 10000
# 기존 방식: 무조건 512슬롯씩 잡으므로 총 메모리를 512로 나눈 값이 최대 사용자 수
max_users_contiguous = hypothetical_memory // max_seq_len
# 페이징 방식: 요청당 평균 페이징 할당량으로 나눠서 최대 사용자 수 계산
avg_paged = total_paged_allocated // len(requests)
max_users_paged = hypothetical_memory // avg_paged if avg_paged > 0 else 0
```
</details>


### 4.1 결과
```sh
=================================================================
Task 4: PagedAttention - vLLM's Solution
=================================================================

Page size: 16 tokens per page
Contiguous allocation: 512 tokens per request (worst-case)

--- PAGED ALLOCATION (like vLLM's PagedAttention) ---

  Request 1: 45 tokens -> 3 pages (48 slots)
    Pages: [##|##|##]  waste: 6.2%
  Request 2: 128 tokens -> 8 pages (128 slots)
    Pages: [##|##|##|##|##|##|##|##]  waste: 0.0%
  Request 3: 23 tokens -> 2 pages (32 slots)
    Pages: [##|##]  waste: 28.1%
  Request 4: 256 tokens -> 16 pages (256 slots)
    Pages: [##|##|##|##|##|##|##|##|##|##|##|##|##|##|##|##]  waste: 0.0%
  Request 5: 67 tokens -> 5 pages (80 slots)
    Pages: [##|##|##|##|##]  waste: 16.2%

--- SIDE-BY-SIDE COMPARISON ---
Method          Total Allocated   Total Used   Utilization
---------------------------------------------------------
Contiguous             2560 slots      519 slots         20.3%
Paged                   544 slots      519 slots         95.4%

Memory saved: 2016 slots (4.7x less memory)

--- CONCURRENT USER IMPACT ---
  With 10000 total memory slots:
  - Contiguous: 19 concurrent users
  - Paged:      92 concurrent users
  - Improvement: 4.8x more users!

--- OS PAGING ANALOGY ---
  Contiguous = reserving an entire row of seats for each person
  Paged      = giving seats one at a time as people sit down

  Just like OS virtual memory:
  - OS divides RAM into fixed-size pages (typically 4KB)
  - Processes get pages on demand, not large contiguous blocks
  - vLLM does the same for KV cache during LLM inference

=================================================================
KEY INSIGHT:
- PagedAttention uses small pages (like OS virtual memory)
- No worst-case pre-allocation needed
- Memory utilization: 20% -> 95%
- This frees memory to serve MORE concurrent users
- Next: Let's use this in practice with vLLM's API server (Task 5)
=================================================================

Task 4 Complete!
Next: python /root/code/task_5_api_server.py
```

### 5. task_5_api_server.py

- OpanAI 호환되는 api로 서버 기동 
- 서버에 api 요청

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 5: Launch vLLM as an OpenAI-Compatible API Server
Serve SmolLM via HTTP and interact using the OpenAI Python client.
"""

import os
import sys
import time
import subprocess

os.environ["VLLM_TARGET_DEVICE"] = "cpu"
os.environ["VLLM_ENABLE_V1_MULTIPROCESSING"] = "0"
os.environ.pop("VLLM_CPU_KVCACHE_SPACE", None)
os.environ["TORCHDYNAMO_DISABLE"] = "1"

# max_model_len=128 - plenty for the 20-user load test in Task 6.
KV_CACHE_BYTES = 128 * 1024 * 1024


def wait_for_server(url, timeout=120):
    """Wait for the vLLM server to be ready."""
    import requests

    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = requests.get(f"{url}/health")
            if resp.status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(2)
        elapsed = int(time.time() - start)
        print(f"  Waiting for server... ({elapsed}s)", end="\r")
    return False


def main():
    print("=" * 65)
    print("Task 5: vLLM OpenAI-Compatible API Server")
    print("=" * 65)

    model_name = "HuggingFaceTB/SmolLM-135M"
    server_url = "http://localhost:8000"
    prompt = "What is inference in machine learning?"

    print(f"\nModel: {model_name}")
    print(f"Server URL: {server_url}")
    print(f"Prompt: \"{prompt}\"")
    print("-" * 65)

    # --- START vLLM SERVER ---
    print("\nStarting vLLM server (this may take a moment)...")
    print("Command: python -m vllm.entrypoints.openai.api_server --model HuggingFaceTB/SmolLM-135M --port 8000")

    # Check if server is already running
    import requests
    try:
        resp = requests.get(f"{server_url}/health")
        if resp.status_code == 200:
            print("  Server is already running!")
    except Exception:
        # Start the server detached, logging to a file. Piping to this
        # script would break the server once the script exits (closed
        # pipes) or stall it during startup (full pipe buffers).
        os.makedirs("/root/markers", exist_ok=True)
        server_log = open("/root/markers/vllm_server.log", "w")
        server_process = subprocess.Popen(
            [
                sys.executable, "-m", "vllm.entrypoints.openai.api_server",
                "--model", model_name,
                "--port", "8000",
                "--max-model-len", "128",
                "--kv-cache-memory-bytes", str(KV_CACHE_BYTES),
                "--enforce-eager",
            ],
            stdout=server_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        print(f"  Server process started (PID: {server_process.pid})")
        print("  Server logs: /root/markers/vllm_server.log")

        # Save PID for later tasks
        with open("/root/markers/vllm_server_pid.txt", "w") as f:
            f.write(str(server_process.pid))

    # Wait for server to be ready
    print("\n  Waiting for server to be ready...")
    if wait_for_server(server_url):
        print("  Server is ready!")
    else:
        print("  ERROR: Server did not start within timeout.")
        print("  Try running manually: vllm serve HuggingFaceTB/SmolLM-135M --port 8000")
        return

    # --- SEND REQUEST ---
    print(f"\n--- SENDING REQUEST ---")
    print(f"Endpoint: {server_url}/v1/completions")

    from openai import OpenAI

    # TODO 1: Configure the OpenAI client to point to the local vLLM server
    # Hint: Point the client to the local vLLM server URL
    client = OpenAI(base_url=f"{server_url}/v1", api_key="not-needed")  # TODO: Set to "http://localhost:8000/v1" and "not-needed"

    # TODO 2: Send a completion request
    # Hint: Use the model_name variable
    start_time = time.time()
    response = client.completions.create(
        model=model_name,  # TODO: Set to model_name
        prompt=prompt,
        max_tokens=50,
        temperature=0.7,
    )
    end_time = time.time()

    # Extract response
    response_text = response.choices[0].text
    latency = end_time - start_time

    # --- RESPONSE ---
    print(f"\n--- RESPONSE ---")
    print(f"Model: {response.model}")
    print(f"Response: {response_text[:200]}")
    print(f"Latency: {latency:.2f}s")

    if response.usage:
        print(f"Prompt tokens: {response.usage.prompt_tokens}")
        print(f"Completion tokens: {response.usage.completion_tokens}")

    # --- API DETAILS ---
    print(f"\n--- API DETAILS ---")
    print(f"Endpoint: {server_url}/v1/completions")
    print(f"Format: OpenAI-compatible (drop-in replacement)")
    print(f"Auth: No API key needed (local server)")

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- vLLM serves an OpenAI-compatible API out of the box")
    print("- Any app using the OpenAI SDK works with vLLM - zero code changes")
    print("- This is how you self-host LLMs in production")
    print("- The server stays running for Tasks 6-8")
    print("=" * 65)

    # Create marker
    with open("/root/markers/task5_complete.txt", "w") as f:
        f.write("TASK_5_COMPLETE\n")

    print("\nTask 5 Complete!")
    print("Next: python /root/code/task_6_multi_user_load.py")


if __name__ == "__main__":
    main()

```

</details>

<details>
<summary> 핵심 요약</summary>

1. vLLM 서버를 백그라운드로 실행
2. OpenAI SDK를 활용하여 vLLM 서버를 호출한다. 여기서 봐야할 점은 특정 모델에 종속되지 않고, 다양한 모델을 활용할수 있다는 점이다. 

```python
KV_CACHE_BYTES = 128 * 1024 * 1024  # KV 캐시에 할당할 메모리 크기 (128MB)

model_name = "HuggingFaceTB/SmolLM-135M"
server_url = "http://localhost:8000"
prompt = "What is inference in machine learning?"

# --- vLLM 서버를 별도 프로세스로 실행 ---
# python -m vllm.entrypoints.openai.api_server 가 vLLM을 OpenAI 호환 API 서버 형태로 띄우는 실제 명령어
server_process = subprocess.Popen(
    [
        sys.executable, "-m", "vllm.entrypoints.openai.api_server",
        "--model", model_name,          # 서빙할 모델
        "--port", "8000",               # API 서버 포트
        "--max-model-len", "128",       # 최대 시퀀스 길이 제한
        "--kv-cache-memory-bytes", str(KV_CACHE_BYTES),  # KV 캐시용 메모리 크기 지정
        "--enforce-eager",              # CUDA 그래프 최적화 끄고 즉시 실행 모드 (디버깅/저사양 환경용)
    ],
    stdout=server_log,
    stderr=subprocess.STDOUT,
    start_new_session=True,   # 이 스크립트가 종료돼도 서버는 계속 살아있게 함
)

# 서버가 완전히 뜰 때까지 /health 엔드포인트를 폴링하며 대기
wait_for_server(server_url)

# --- OpenAI SDK 사용 ---
from openai import OpenAI

# base_url만 로컬 vLLM 서버로 바꾸면 됨 - OpenAI 쓰던 코드 그대로 재사용 가능
client = OpenAI(base_url=f"{server_url}/v1", api_key="not-needed")

# OpenAI의 completions API와 완전히 동일한 문법으로 호출
response = client.completions.create(
    model=model_name,     # 어떤 모델로 응답할지 (서버에 로드된 모델명과 일치해야 함)
    prompt=prompt,         # 입력 프롬프트
    max_tokens=50,         # 생성할 최대 토큰 수
    temperature=0.7,       # 샘플링 다양성 조절
)

response_text = response.choices[0].text  # 생성된 텍스트 추출
```

</details>

### 5.1 결과
```sh
python task_5_api_server.py =================================================================
Task 5: vLLM OpenAI-Compatible API Server
=================================================================

Model: HuggingFaceTB/SmolLM-135M
Server URL: http://localhost:8000
Prompt: "What is inference in machine learning?"
-----------------------------------------------------------------

Starting vLLM server (this may take a moment)...
Command: python -m vllm.entrypoints.openai.api_server --model HuggingFaceTB/SmolLM-135M --port 8000
  Server process started (PID: 6170)
  Server logs: /root/markers/vllm_server.log

  Waiting for server to be ready...
  Server is ready!er... (24s)

--- SENDING REQUEST ---
Endpoint: http://localhost:8000/v1/completions

--- RESPONSE ---
Model: HuggingFaceTB/SmolLM-135M
Response: 
Inference is a component of machine learning that allows an algorithm to make predictions based on data. It is a type of optimization problem in machine learning that involves finding the best parame
Latency: 3.95s
Prompt tokens: 7
Completion tokens: 50

--- API DETAILS ---
Endpoint: http://localhost:8000/v1/completions
Format: OpenAI-compatible (drop-in replacement)
Auth: No API key needed (local server)

=================================================================
KEY INSIGHT:
- vLLM serves an OpenAI-compatible API out of the box
- Any app using the OpenAI SDK works with vLLM - zero code changes
- This is how you self-host LLMs in production
- The server stays running for Tasks 6-8
=================================================================

Task 5 Complete!
Next: python /root/code/task_6_multi_user_load.py

```

### 6. task_6_multi_user_load.py
- vLLM 서버에 1/5/10/20 사용자에 대한 동시 요청 
- 처리량 측정 
- 결과 저장 `/root/markers/load_test_results.json`

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 6: Multi-User Throughput Under Load
Stress-test the vLLM server with concurrent requests.
"""

import os
import sys
import time
import json
import asyncio


async def send_request(session, url, model, prompt, max_tokens=50):
    """Send a single completion request and return timing info."""
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }
    start = time.time()
    try:
        async with session.post(
            f"{url}/v1/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
        ) as resp:
            data = await resp.json()
            end = time.time()
            if resp.status != 200:
                return {
                    "latency": end - start,
                    "tokens": 0,
                    "success": False,
                    "error": f"HTTP {resp.status}: {str(data)[:150]}",
                }
            completion_tokens = data.get("usage", {}).get("completion_tokens", 0)
            return {
                "latency": end - start,
                "tokens": completion_tokens,
                "success": True,
            }
    except Exception as e:
        return {"latency": time.time() - start, "tokens": 0, "success": False, "error": str(e)}


async def run_load_test(url, model, prompts, num_concurrent):
    """Run a load test with the given number of concurrent users."""
    import aiohttp

    async with aiohttp.ClientSession() as session:
        tasks = []
        for i in range(num_concurrent):
            prompt = prompts[i % len(prompts)]
            tasks.append(send_request(session, url, model, prompt))

        start_time = time.time()
        results = await asyncio.gather(*tasks)
        total_time = time.time() - start_time

    return results, total_time


def main():
    print("=" * 65)
    print("Task 6: Multi-User Throughput Under Load")
    print("=" * 65)

    model_name = "HuggingFaceTB/SmolLM-135M"
    server_url = "http://localhost:8000"

    # Verify server is running
    import requests
    try:
        resp = requests.get(f"{server_url}/health")
        if resp.status_code != 200:
            raise Exception("Server not healthy")
    except Exception:
        print("\nERROR: vLLM server is not running on port 8000.")
        print("Run Task 5 first: python /root/code/task_5_api_server.py")
        return

    print(f"\nServer: {server_url}")
    print(f"Model: {model_name}")
    print("-" * 65)

    # Diverse prompts to simulate real users
    prompts = [
        "What is machine learning?",
        "Explain neural networks briefly.",
        "How does a transformer model work?",
        "What is natural language processing?",
        "Describe deep learning in one paragraph.",
        "What are tokens in the context of LLMs?",
        "How is AI used in healthcare?",
        "What is the difference between AI and ML?",
        "Explain what fine-tuning means.",
        "What is transfer learning?",
    ]

    # TODO 1: Create the list of concurrent user counts to test
    # Hint: Start small and increase to see how throughput scales
    concurrent_users = [1, 5, 10, 20]  # TODO: Set to [1, 5, 10, 20]

    print(f"\nLoad test plan: {concurrent_users} concurrent users")
    print(f"Each user sends 1 request with max_tokens=50\n")

    results_table = []

    for num_users in concurrent_users:
        print(f"  Testing with {num_users} concurrent user(s)...", end=" ")

        test_results, total_time = asyncio.run(
            run_load_test(server_url, model_name, prompts, num_users)
        )

        successful = [r for r in test_results if r["success"]]
        total_tokens = sum(r["tokens"] for r in successful)
        avg_latency = sum(r["latency"] for r in successful) / len(successful) if successful else 0

        # TODO 2: Calculate aggregate throughput
        # Hint: Divide total tokens by total time
        throughput = total_tokens / total_time  # TODO: Set to total_tokens / total_time

        results_table.append({
            "users": num_users,
            "total_tokens": total_tokens,
            "total_time": total_time,
            "throughput": throughput,
            "avg_latency": avg_latency,
            "success_rate": len(successful) / len(test_results) * 100,
        })

        print(f"done ({throughput:.1f} tok/s, {avg_latency:.2f}s avg latency)")

        failed = [r for r in test_results if not r["success"]]
        if failed:
            print(f"    WARNING: {len(failed)} request(s) failed.")
            print(f"    First error: {failed[0].get('error', 'unknown')}")

    # --- RESULTS TABLE ---
    print(f"\n--- LOAD TEST RESULTS ---")
    print(f"{'Users':>6} {'Total Tokens':>13} {'Time (s)':>9} {'Throughput':>12} {'Avg Latency':>12} {'Success':>8}")
    print("-" * 66)
    for r in results_table:
        print(
            f"{r['users']:>6} "
            f"{r['total_tokens']:>13} "
            f"{r['total_time']:>8.2f}s "
            f"{r['throughput']:>9.1f} tok/s "
            f"{r['avg_latency']:>10.2f}s "
            f"{r['success_rate']:>7.0f}%"
        )

    # --- SCALING ANALYSIS ---
    if len(results_table) >= 2:
        baseline = results_table[0]
        peak = max(results_table, key=lambda r: r["throughput"])
        scaling = peak["throughput"] / baseline["throughput"] if baseline["throughput"] > 0 else 0

        print(f"\n--- SCALING ANALYSIS ---")
        print(f"  Baseline (1 user): {baseline['throughput']:.1f} tok/s")
        print(f"  Peak ({peak['users']} users): {peak['throughput']:.1f} tok/s")
        print(f"  Scaling factor: {scaling:.1f}x throughput improvement")

    # Save results for dashboard
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/load_test_results.json", "w") as f:
        json.dump(results_table, f, indent=2)

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- Throughput SCALES with concurrent users")
    print("- vLLM uses continuous batching - does not wait for batch to fill")
    print("- PagedAttention allows efficient KV cache sharing across requests")
    print("- Per-request latency increases but total throughput improves")
    print("- This is the core value of vLLM: high-throughput multi-user serving")
    print("=" * 65)

    # Create marker
    with open("/root/markers/task6_complete.txt", "w") as f:
        f.write("TASK_6_COMPLETE\n")

    print("\nTask 6 Complete!")
    print("Next: python /root/code/task_7_tuning.py")


if __name__ == "__main__":
    main()
```
</details>

<details>
<summary> 핵심 요약</summary>

1. `send_request` vLLM 서버(/v1/completions)에 요청을 보내어 지연시간 / 토큰 수 측정 
2. `run_load_test` asyncio.gather() 함수로 N개의 요청을 동시 처리, 사용자 순차적으로 증가하여 동시 사용자 수에 대한 처리량 변화 관찰

해당 결과로 알수 있듯이 토큰 처리량은 약 `12.7배` 빨라졌지만 레이턴시는 `1.6배`가 올랐을 뿐이다. 이러한 이유에는 vLLM이 기본적으로 `Continuous Batching`와 `Paged Attention`를 활용하여 여러 사용자의 요청을 동시에 높을 효율로 처리하는 고성능 서빙이기 때문이다.

```sh
# 1 / 5 / 10 / 20 순으로 유저 수 증가
# 요청 당 최대 토큰 50제한 
--- LOAD TEST RESULTS ---
 Users  Total Tokens  Time (s)   Throughput  Avg Latency  Success
------------------------------------------------------------------
     1            50     3.89s      12.9 tok/s       3.89s     100%
     5           250     4.91s      50.9 tok/s       4.90s     100%
    10           500     5.19s      96.4 tok/s       5.17s     100%
    20          1000     6.10s     163.9 tok/s       6.09s     100%

--- SCALING ANALYSIS ---
  Baseline (1 user): 12.9 tok/s
  Peak (20 users): 163.9 tok/s
  Scaling factor: 12.7x throughput improvement
```

```python
async def send_request(session, url, model, prompt, max_tokens=50):
    # vLLM 서버의 completions 엔드포인트에 보낼 요청 payload 구성
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }
    start = time.time()
    try:
        # OpenAI SDK 대신 aiohttp로 직접 HTTP POST
        # (여러 요청을 비동기/동시에 보내기 위해 저수준 HTTP 클라이언트 사용)
        async with session.post(
            f"{url}/v1/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
        ) as resp:
            data = await resp.json()
            end = time.time()
            if resp.status != 200:
                # 실패한 요청은 latency=0 토큰, success=False로 기록
                return {"latency": end - start, "tokens": 0, "success": False, "error": ...}

            # 응답에서 실제 생성된 토큰 수 추출 (throughput 계산에 사용)
            completion_tokens = data.get("usage", {}).get("completion_tokens", 0)
            return {"latency": end - start, "tokens": completion_tokens, "success": True}
    except Exception as e:
        return {"latency": time.time() - start, "tokens": 0, "success": False, "error": str(e)}


async def run_load_test(url, model, prompts, num_concurrent):
    import aiohttp

    async with aiohttp.ClientSession() as session:
        tasks = []
        # num_concurrent 명 만큼 요청 태스크를 미리 생성 (아직 실행은 안 함)
        for i in range(num_concurrent):
            prompt = prompts[i % len(prompts)]  # 프롬프트를 순환하며 사용
            tasks.append(send_request(session, url, model, prompt))

        start_time = time.time()
        # 핵심: 모든 요청을 "동시에" 실행 (순차 대기 X)
        # vLLM의 continuous batching이 이 동시 요청들을 하나의 배치로 묶어 처리
        results = await asyncio.gather(*tasks)
        total_time = time.time() - start_time

    return results, total_time


# --- 메인 로직 ---
concurrent_users = [1, 5, 10, 20]  # 테스트할 동시 사용자 수 단계

for num_users in concurrent_users:
    # 동시 사용자 수를 바꿔가며 부하 테스트 반복 실행
    test_results, total_time = asyncio.run(
        run_load_test(server_url, model_name, prompts, num_users)
    )

    successful = [r for r in test_results if r["success"]]
    total_tokens = sum(r["tokens"] for r in successful)
    avg_latency = sum(r["latency"] for r in successful) / len(successful) if successful else 0

    # 전체 처리량(throughput) = 총 생성 토큰 수 / 전체 소요 시간
    # 사용자가 늘어도 vLLM이 배치로 묶어 처리하기 때문에 처리량이 선형적으로 증가하는 걸 확인하는 게 목적
    throughput = total_tokens / total_time
```
</details>


### 6.1 결과

```sh
python task_6_multi_user_load.py 
=================================================================
Task 6: Multi-User Throughput Under Load
=================================================================

Server: http://localhost:8000
Model: HuggingFaceTB/SmolLM-135M
-----------------------------------------------------------------

Load test plan: [1, 5, 10, 20] concurrent users
Each user sends 1 request with max_tokens=50

  Testing with 1 concurrent user(s)... done (12.9 tok/s, 3.89s avg latency)
  Testing with 5 concurrent user(s)... done (50.9 tok/s, 4.90s avg latency)
  Testing with 10 concurrent user(s)... done (96.4 tok/s, 5.17s avg latency)
  Testing with 20 concurrent user(s)... done (163.9 tok/s, 6.09s avg latency)

--- LOAD TEST RESULTS ---
 Users  Total Tokens  Time (s)   Throughput  Avg Latency  Success
------------------------------------------------------------------
     1            50     3.89s      12.9 tok/s       3.89s     100%
     5           250     4.91s      50.9 tok/s       4.90s     100%
    10           500     5.19s      96.4 tok/s       5.17s     100%
    20          1000     6.10s     163.9 tok/s       6.09s     100%

--- SCALING ANALYSIS ---
  Baseline (1 user): 12.9 tok/s
  Peak (20 users): 163.9 tok/s
  Scaling factor: 12.7x throughput improvement

=================================================================
KEY INSIGHT:
- Throughput SCALES with concurrent users
- vLLM uses continuous batching - does not wait for batch to fill
- PagedAttention allows efficient KV cache sharing across requests
- Per-request latency increases but total throughput improves
- This is the core value of vLLM: high-throughput multi-user serving
=================================================================

Task 6 Complete!
Next: python /root/code/task_7_tuning.py
```

### 7. task_7_tuning.py

- Tests 3 vLLM configurations (default, shorter context, limited concurrency)
- 벤치마크 값에 대한 비교 
- 결과 저장 `/root/markers/tuning_results.json`

<details>
<summary> 전체 코드</summary>

```python
#!/usr/bin/env python3
"""
Task 7: Tuning vLLM Parameters for Production
Experiment with key vLLM configuration options.
"""

import os
import sys
import time
import json
import signal
import subprocess
import asyncio

# Configure vLLM for CPU-only execution.
# The lab VM has a 4GB memory limit, so run the engine in-process
# (VLLM_ENABLE_V1_MULTIPROCESSING=0) and cap the KV cache via
# --kv-cache-memory-bytes. VLLM_CPU_KVCACHE_SPACE is deliberately
# unset - it would override the explicit KV cache size.
# The server subprocess inherits this environment.
os.environ["VLLM_TARGET_DEVICE"] = "cpu"
os.environ["VLLM_ENABLE_V1_MULTIPROCESSING"] = "0"
os.environ.pop("VLLM_CPU_KVCACHE_SPACE", None)
os.environ["TORCHDYNAMO_DISABLE"] = "1"

# 128MB holds ~43 full-length sequences for SmolLM-135M at
# max_model_len=128 - plenty for the 10-request benchmarks here.
KV_CACHE_BYTES = 128 * 1024 * 1024


async def send_request(session, url, model, prompt, max_tokens=50):
    """Send a single completion request."""
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }
    start = time.time()
    try:
        async with session.post(
            f"{url}/v1/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
        ) as resp:
            data = await resp.json()
            end = time.time()
            if resp.status != 200:
                return {
                    "latency": end - start,
                    "tokens": 0,
                    "success": False,
                    "error": f"HTTP {resp.status}: {str(data)[:150]}",
                }
            tokens = data.get("usage", {}).get("completion_tokens", 0)
            return {"latency": end - start, "tokens": tokens, "success": True}
    except Exception as e:
        return {"latency": time.time() - start, "tokens": 0, "success": False, "error": str(e)}


async def run_quick_benchmark(url, model, num_requests=10):
    """Run a quick benchmark with concurrent requests."""
    import aiohttp

    prompts = [
        "What is machine learning?",
        "Explain neural networks.",
        "How does AI work?",
        "What are transformers?",
        "Describe deep learning.",
    ]

    async with aiohttp.ClientSession() as session:
        tasks = [
            send_request(session, url, model, prompts[i % len(prompts)])
            for i in range(num_requests)
        ]
        start = time.time()
        results = await asyncio.gather(*tasks)
        total_time = time.time() - start

    successful = [r for r in results if r["success"]]
    failed = [r for r in results if not r["success"]]
    total_tokens = sum(r["tokens"] for r in successful)
    avg_latency = sum(r["latency"] for r in successful) / len(successful) if successful else 0
    throughput = total_tokens / total_time if total_time > 0 else 0

    if failed:
        print(f"  WARNING: {len(failed)} request(s) failed.")
        print(f"  First error: {failed[0].get('error', 'unknown')}")

    return {
        "throughput": throughput,
        "avg_latency": avg_latency,
        "total_tokens": total_tokens,
        "total_time": total_time,
        "success_count": len(successful),
    }


def stop_server():
    """Stop any running vLLM server."""
    pid_file = "/root/markers/vllm_server_pid.txt"
    if os.path.exists(pid_file):
        with open(pid_file, "r") as f:
            pid = int(f.read().strip())
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(2)
            print("  Previous server stopped.")
        except ProcessLookupError:
            pass

    # Also try killing by port
    try:
        result = subprocess.run(
            ["fuser", "-k", "8000/tcp"],
            capture_output=True, timeout=5
        )
    except Exception:
        pass
    time.sleep(1)


def start_server(model, max_model_len, max_num_seqs, swap_space=2):
    """Start vLLM server with given parameters."""
    import requests

    cmd = [
        sys.executable, "-m", "vllm.entrypoints.openai.api_server",
        "--model", model,
        "--port", "8000",
        "--max-model-len", str(max_model_len),
        "--max-num-seqs", str(max_num_seqs),
        "--kv-cache-memory-bytes", str(KV_CACHE_BYTES),
        # swap-space removed in vLLM v0.18+ (shown in output only)
        "--enforce-eager",
    ]

    # Detached with logs to a file - piping to this script would break
    # the server once the script exits or stall it on full pipe buffers.
    os.makedirs("/root/markers", exist_ok=True)
    server_log = open("/root/markers/vllm_server.log", "w")
    proc = subprocess.Popen(
        cmd,
        stdout=server_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    # Save PID
    with open("/root/markers/vllm_server_pid.txt", "w") as f:
        f.write(str(proc.pid))

    # Wait for ready
    timeout = 120
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = requests.get("http://localhost:8000/health")
            if resp.status_code == 200:
                return proc
        except Exception:
            pass
        time.sleep(2)

    return None


def main():
    print("=" * 65)
    print("Task 7: Tuning vLLM Parameters for Production")
    print("=" * 65)

    model_name = "HuggingFaceTB/SmolLM-135M"
    server_url = "http://localhost:8000"
    num_test_requests = 10

    print(f"\nModel: {model_name}")
    print(f"Benchmark: {num_test_requests} concurrent requests per config")
    print("-" * 65)

    # Define configurations to test
    configs = [
        {
            "name": "A: Default",
            "max_model_len": 128,
            "max_num_seqs": 256,
            "swap_space": 1,
        },
        {
            "name": "B: Shorter Context",
            # TODO 1: Set a shorter context length
            # Hint: Shorter context = less memory per request
            "max_model_len": 64,  # TODO: Set to 64
            "max_num_seqs": 256,
            "swap_space": 1,
        },
        {
            "name": "C: Limited Concurrency",
            "max_model_len": 64,
            # TODO 2: Limit concurrent sequences
            # Hint: Fewer concurrent sequences = less memory pressure
            "max_num_seqs": 8,  # TODO: Set to 8
            "swap_space": 1,
        },
    ]

    results = []

    for i, config in enumerate(configs):
        print(f"\n--- CONFIG {config['name']} ---")
        print(f"  max_model_len={config['max_model_len']}, "
              f"max_num_seqs={config['max_num_seqs']}, "
              f"swap_space={config['swap_space']}GB")

        # Stop existing server
        print("  Stopping previous server...")
        stop_server()

        # Start with new config
        print(f"  Starting server with config {config['name']}...")
        proc = start_server(
            model_name,
            config["max_model_len"],
            config["max_num_seqs"],
            config["swap_space"],
        )

        if proc is None:
            print("  ERROR: Server failed to start with this config.")
            results.append({"config": config["name"], "throughput": 0, "avg_latency": 0})
            continue

        print("  Server ready! Running benchmark...")
        benchmark = asyncio.run(run_quick_benchmark(server_url, model_name, num_test_requests))

        results.append({
            "config": config["name"],
            "max_model_len": config["max_model_len"],
            "max_num_seqs": config["max_num_seqs"],
            "throughput": benchmark["throughput"],
            "avg_latency": benchmark["avg_latency"],
            "total_tokens": benchmark["total_tokens"],
        })

        print(f"  Result: {benchmark['throughput']:.1f} tok/s, "
              f"{benchmark['avg_latency']:.2f}s avg latency")

    # --- COMPARISON TABLE ---
    print(f"\n--- CONFIGURATION COMPARISON ---")
    print(f"{'Config':<22} {'max_model_len':>14} {'max_num_seqs':>13} {'Throughput':>11} {'Latency':>9}")
    print("-" * 72)
    for r in results:
        print(
            f"{r['config']:<22} "
            f"{r.get('max_model_len', 'N/A'):>14} "
            f"{r.get('max_num_seqs', 'N/A'):>13} "
            f"{r['throughput']:>8.1f} tok/s "
            f"{r['avg_latency']:>7.2f}s"
        )

    # --- KEY PARAMETERS ---
    print(f"\n--- KEY PARAMETERS EXPLAINED ---")
    print(f"  max_model_len:  Maximum context length per request.")
    print(f"                  Lower = less memory per request.")
    print(f"  max_num_seqs:   Maximum concurrent sequences in a batch.")
    print(f"                  Controls concurrency vs per-request resources.")
    print(f"  swap_space:     CPU swap space (GB) for KV cache overflow.")
    print(f"                  Extends capacity beyond available RAM.")

    # Save results
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/tuning_results.json", "w") as f:
        json.dump(results, f, indent=2)

    # --- KEY INSIGHT ---
    print("\n" + "=" * 65)
    print("KEY INSIGHT:")
    print("- Lower max_model_len saves memory per request")
    print("- max_num_seqs controls concurrency vs per-request resources")
    print("- swap_space extends KV cache to CPU RAM when memory is tight")
    print("- Always tune based on YOUR workload pattern")
    print("- Next: Build a monitoring dashboard to track these metrics (Task 8)")
    print("=" * 65)

    # Create marker
    with open("/root/markers/task7_complete.txt", "w") as f:
        f.write("TASK_7_COMPLETE\n")

    print("\nTask 7 Complete!")
    print("Next: python /root/code/task_8_dashboard.py")


if __name__ == "__main__":
    main()

```

</details>

<details>
<summary> 핵심 요약</summary>

vLLM 서버를 여러 설정으로 바꿔가며 재시작하면서 처리량 / 레이선시가 어떻게 달라지는 비교한다. 

- max_model_len : 최대 Conetxt 길이로 KV Cache 크기를 결정한다. 길이가 길면 메모리 사용량 증가한다. 이 값을 낮춘다면 KV Cache에 저장을 적게 하기 떄문에 메모리 절약ㄱ 및 더 많은 요청을 수용할수 있지만 긴 프롬프트는 처리할수 없다.
- max_num_seqs : 최대 배치 크기를 의미한다. 값이 높다면 처리량 증가하고 메모리 사용량이 증가하지만 값을 낮게하면 메모리가 감소하는 대신, 처리량이 감소한다.
- swap_space : KV Cache를 cpu ram으로 확장한다. gpu 매모리가 부족하면 cpu ram을 활용하여 더 많은 요청을 처리할수 있게한다. 대신 메모리가 병목이 발생할수 있다

1. Config A는 기본 vLLM 설정으로 약 92.7/s 토큰을 처리한다.
2. Config B는 KV cache 메모리가 감소하여, 처리 효율이 약간 향상되었지만, 크게 유의미한 성능 차이가 보이진 않는다.
3. Config C는 최대 배치 크기를 감소하여, gpu 활용률이 많이 떨어져 처리랑이 크게 감소할 것을 확인할 수가 있따.

```sh
--- CONFIGURATION COMPARISON ---
Config                  max_model_len  max_num_seqs  Throughput   Latency
------------------------------------------------------------------------
A: Default                        128           256     92.7 tok/s    5.25s
B: Shorter Context                 64           256     94.6 tok/s    5.15s
C: Limited Concurrency             64             8     61.0 tok/s    5.29s
```

```python
def stop_server():
    """실행 중인 vLLM 서버를 종료"""
    pid_file = "/root/markers/vllm_server_pid.txt"
    if os.path.exists(pid_file):
        with open(pid_file, "r") as f:
            pid = int(f.read().strip())
        try:
            os.kill(pid, signal.SIGTERM)  # 저장해둔 PID로 서버 프로세스 종료
            time.sleep(2)
        except ProcessLookupError:
            pass

    # PID로 못 잡았을 경우를 대비해 포트 기준으로도 강제 종료
    subprocess.run(["fuser", "-k", "8000/tcp"], capture_output=True, timeout=5)


def start_server(model, max_model_len, max_num_seqs, swap_space=2):
    """주어진 파라미터로 vLLM 서버를 새로 실행"""
    cmd = [
        sys.executable, "-m", "vllm.entrypoints.openai.api_server",
        "--model", model,
        "--port", "8000",
        "--max-model-len", str(max_model_len),   # 요청당 최대 컨텍스트 길이 (메모리 사용량 결정)
        "--max-num-seqs", str(max_num_seqs),     # 한 배치에서 동시에 처리할 최대 시퀀스 수
        "--kv-cache-memory-bytes", str(KV_CACHE_BYTES),
        "--enforce-eager",
    ]

    proc = subprocess.Popen(cmd, stdout=server_log, stderr=subprocess.STDOUT, start_new_session=True)

    # 새로 뜬 프로세스 PID를 저장 (다음에 stop_server()가 종료할 때 사용)
    with open("/root/markers/vllm_server_pid.txt", "w") as f:
        f.write(str(proc.pid))

    # /health 엔드포인트가 200을 줄 때까지 폴링하며 대기
    while time.time() - start < timeout:
        resp = requests.get("http://localhost:8000/health")
        if resp.status_code == 200:
            return proc
        time.sleep(2)

    return None


# --- 비교할 설정 3가지 ---
configs = [
    {"name": "A: Default", "max_model_len": 128, "max_num_seqs": 256, "swap_space": 1},
    {"name": "B: Shorter Context", "max_model_len": 64, "max_num_seqs": 256, "swap_space": 1},  # 컨텍스트만 줄임
    {"name": "C: Limited Concurrency", "max_model_len": 64, "max_num_seqs": 8, "swap_space": 1},  # 동시성도 줄임
]

for config in configs:
    stop_server()  # 이전 설정으로 뜬 서버 종료
    proc = start_server(model_name, config["max_model_len"], config["max_num_seqs"], config["swap_space"])  # 새 설정으로 재시작

    # Task 5, 6과 동일한 방식(HTTP POST /v1/completions)으로 부하 테스트
    benchmark = asyncio.run(run_quick_benchmark(server_url, model_name, num_test_requests))
```

</details>


### 7.1 결과
```sh
python task_7_tuning.py 
=================================================================
Task 7: Tuning vLLM Parameters for Production
=================================================================

Model: HuggingFaceTB/SmolLM-135M
Benchmark: 10 concurrent requests per config
-----------------------------------------------------------------

--- CONFIG A: Default ---
  max_model_len=128, max_num_seqs=256, swap_space=1GB
  Stopping previous server...
  Previous server stopped.
  Starting server with config A: Default...
  Server ready! Running benchmark...
  Result: 92.7 tok/s, 5.25s avg latency

--- CONFIG B: Shorter Context ---
  max_model_len=64, max_num_seqs=256, swap_space=1GB
  Stopping previous server...
  Previous server stopped.
  Starting server with config B: Shorter Context...
  Server ready! Running benchmark...
  Result: 94.6 tok/s, 5.15s avg latency

--- CONFIG C: Limited Concurrency ---
  max_model_len=64, max_num_seqs=8, swap_space=1GB
  Stopping previous server...
  Previous server stopped.
  Starting server with config C: Limited Concurrency...
  Server ready! Running benchmark...
  Result: 61.0 tok/s, 5.29s avg latency

--- CONFIGURATION COMPARISON ---
Config                  max_model_len  max_num_seqs  Throughput   Latency
------------------------------------------------------------------------
A: Default                        128           256     92.7 tok/s    5.25s
B: Shorter Context                 64           256     94.6 tok/s    5.15s
C: Limited Concurrency             64             8     61.0 tok/s    5.29s

--- KEY PARAMETERS EXPLAINED ---
  max_model_len:  Maximum context length per request.
                  Lower = less memory per request.
  max_num_seqs:   Maximum concurrent sequences in a batch.
                  Controls concurrency vs per-request resources.
  swap_space:     CPU swap space (GB) for KV cache overflow.
                  Extends capacity beyond available RAM.

=================================================================
KEY INSIGHT:
- Lower max_model_len saves memory per request
- max_num_seqs controls concurrency vs per-request resources
- swap_space extends KV cache to CPU RAM when memory is tight
- Always tune based on YOUR workload pattern
- Next: Build a monitoring dashboard to track these metrics (Task 8)
=================================================================

Task 7 Complete!
Next: python /root/code/task_8_dashboard.py
```

### 8. task_8_dashboard.py

8장은 간단하게 기존 task에서 수행했던 내역들을 웹 html로 출력하기 때문에 별도로 기술하지 않는다.

<details>
<summary><strong>전체 코드</strong></summary>


```python
#!/usr/bin/env python3
"""
Task 8: Production Monitoring Dashboard (Capstone)
Build a live Gradio dashboard to monitor vLLM inference metrics.
"""

import os
import sys
import json
import time
import asyncio
import threading

# Configure vLLM for CPU-only execution (in case server needs restart)
os.environ["VLLM_TARGET_DEVICE"] = "cpu"
os.environ["VLLM_ENABLE_V1_MULTIPROCESSING"] = "0"
os.environ.pop("VLLM_CPU_KVCACHE_SPACE", None)
os.environ["TORCHDYNAMO_DISABLE"] = "1"

# Disable Gradio analytics to avoid CORS errors behind reverse proxy
os.environ["GRADIO_ANALYTICS_ENABLED"] = "False"


def main():
    print("=" * 65)
    print("Task 8: Production Monitoring Dashboard (Capstone)")
    print("=" * 65)

    import gradio as gr
    import requests

    server_url = "http://localhost:8000"
    model_name = "HuggingFaceTB/SmolLM-135M"

    # Verify server is running
    try:
        resp = requests.get(f"{server_url}/health")
        if resp.status_code != 200:
            raise Exception("Server not healthy")
    except Exception:
        print("\nERROR: vLLM server is not running on port 8000.")
        print("Run Task 5 first: python /root/code/task_5_api_server.py")
        return

    print(f"\nServer: {server_url} (running)")
    print(f"Dashboard will be available at: http://localhost:7860")
    print("-" * 65)

    # Load previous results
    hf_baseline = {}
    if os.path.exists("/root/markers/hf_baseline.txt"):
        with open("/root/markers/hf_baseline.txt", "r") as f:
            for line in f:
                key, value = line.strip().split("=")
                hf_baseline[key] = float(value)

    vllm_baseline = {}
    if os.path.exists("/root/markers/vllm_baseline.txt"):
        with open("/root/markers/vllm_baseline.txt", "r") as f:
            for line in f:
                key, value = line.strip().split("=")
                vllm_baseline[key] = float(value)

    load_test_results = []
    if os.path.exists("/root/markers/load_test_results.json"):
        with open("/root/markers/load_test_results.json", "r") as f:
            load_test_results = json.load(f)

    tuning_results = []
    if os.path.exists("/root/markers/tuning_results.json"):
        with open("/root/markers/tuning_results.json", "r") as f:
            tuning_results = json.load(f)

    # TODO 1: Send a test request to the vLLM server
    # Hint: Use the requests library to send a POST request
    def get_live_metrics():
        """Send a test request and return latency and token count."""
        try:
            payload = {
                "model": model_name,
                "prompt": "Hello, how are you?",
                "max_tokens": 20,
                "temperature": 0.7,
            }
            start = time.time()
            resp = requests.post(  # TODO: Set to requests.post
                f"{server_url}/v1/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            latency = time.time() - start
            data = resp.json()
            tokens = data.get("usage", {}).get("completion_tokens", 0)
            tps = tokens / latency if latency > 0 else 0
            return {
                "latency": round(latency, 3),
                "tokens": tokens,
                "tokens_per_second": round(tps, 1),
                "status": "healthy",
            }
        except Exception as e:
            return {
                "latency": 0,
                "tokens": 0,
                "tokens_per_second": 0,
                "status": f"error: {str(e)}",
            }

    # TODO 2: Build the comparison chart data
    # Hint: Use the baseline values loaded above
    hf_tps = hf_baseline.get("tokens_per_second", 0)
    vllm_tps = vllm_baseline.get("tokens_per_second", 0)
    comparison_data = {
        "Engine": ["HuggingFace", "vLLM"],
        "Tokens per Second": [hf_tps, vllm_tps],  # TODO: Set to hf_tps, vllm_tps
    }

    # TODO 3: Calculate the improvement ratio
    # Hint: Divide vLLM speed by HuggingFace speed
    improvement = vllm_tps / hf_tps if hf_tps > 0 else 0  # TODO: Set to vllm_tps / hf_tps

    # --- THEME AND CSS (following llm-settings-lab pattern) ---
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    def make_comparison_chart():
        """Create HF vs vLLM comparison bar chart."""
        fig, ax = plt.subplots(figsize=(5, 3.5))
        engines = ["HuggingFace", "vLLM"]
        values = [hf_tps, vllm_tps]
        colors = ["#ef4444", "#22c55e"]
        bars = ax.bar(engines, values, color=colors, width=0.5, edgecolor="white")
        ax.set_ylabel("Tokens per Second")
        ax.set_title("Single Request Throughput")
        for bar, val in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
                    f"{val:.1f}", ha="center", fontweight="bold")
        ax.set_ylim(0, max(values) * 1.3 if max(values) > 0 else 10)
        fig.tight_layout()
        return fig

    def make_load_chart():
        """Create load test throughput chart."""
        if not load_test_results:
            return None
        fig, ax = plt.subplots(figsize=(6, 3.5))
        users = [str(r["users"]) for r in load_test_results]
        throughputs = [r["throughput"] for r in load_test_results]
        bars = ax.bar(users, throughputs, color="#3b82f6", width=0.5, edgecolor="white")
        ax.set_xlabel("Concurrent Users")
        ax.set_ylabel("Tokens per Second")
        ax.set_title("Throughput by Concurrent Users")
        for bar, val in zip(bars, throughputs):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
                    f"{val:.1f}", ha="center", fontsize=8)
        ax.set_ylim(0, max(throughputs) * 1.3 if max(throughputs) > 0 else 10)
        fig.tight_layout()
        return fig

    def make_tuning_chart():
        """Create tuning results chart."""
        if not tuning_results:
            return None
        fig, ax = plt.subplots(figsize=(6, 3.5))
        configs = [r["config"] for r in tuning_results]
        throughputs = [r["throughput"] for r in tuning_results]
        bars = ax.bar(configs, throughputs, color="#a855f7", width=0.5, edgecolor="white")
        ax.set_ylabel("Tokens per Second")
        ax.set_title("Throughput by Configuration")
        for bar, val in zip(bars, throughputs):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
                    f"{val:.1f}", ha="center", fontsize=8)
        ax.set_ylim(0, max(throughputs) * 1.3 if max(throughputs) > 0 else 10)
        fig.tight_layout()
        return fig

    # Custom CSS - matching llm-settings-lab pattern with !important
    custom_css = """
    .gradio-container {
        max-width: 100% !important;
        padding: 40px 80px !important;
    }

    h1, h2, h3 {
        color: #29ddff !important;
    }

    table {
        border-collapse: collapse !important;
        width: 100% !important;
        margin-bottom: 16px !important;
    }

    th {
        background: #161b22 !important;
        color: #29ddff !important;
        padding: 10px 12px !important;
        text-align: left !important;
    }

    td {
        padding: 10px 12px !important;
        border-bottom: 1px solid #29ddff22 !important;
    }

    tr:last-child td {
        border-bottom: none !important;
    }

    blockquote {
        border-left: 4px solid #29ddff !important;
        padding-left: 12px !important;
    }

    button.primary {
        background: linear-gradient(135deg, #a5fecb, #12d8fa, #1fa2ff) !important;
        color: #0a0e14 !important;
        font-weight: 600 !important;
    }

    button.primary:hover {
        background: linear-gradient(135deg, #12d8fa, #1fa2ff, #7c3aed) !important;
    }
    """

    # KodeKloud Brand Theme (same as llm-settings-lab)
    kk_theme = gr.themes.Base(
        primary_hue=gr.themes.colors.cyan,
        secondary_hue=gr.themes.colors.purple,
        neutral_hue=gr.themes.colors.slate,
    ).set(
        body_background_fill="#0a0e14",
        body_background_fill_dark="#0a0e14",
        background_fill_primary="#161b22",
        background_fill_primary_dark="#161b22",
        background_fill_secondary="#1e293b",
        background_fill_secondary_dark="#1e293b",
        body_text_color="#ffffff",
        body_text_color_dark="#ffffff",
        body_text_color_subdued="#94a3b8",
        body_text_color_subdued_dark="#94a3b8",
        border_color_primary="#29ddff33",
        border_color_primary_dark="#29ddff33",
        input_background_fill="#161b22",
        input_background_fill_dark="#161b22",
        input_border_color="#29ddff33",
        input_border_color_dark="#29ddff33",
        button_primary_background_fill="#29ddff",
        button_primary_background_fill_dark="#29ddff",
        button_primary_background_fill_hover="#12d8fa",
        button_primary_background_fill_hover_dark="#12d8fa",
        button_primary_text_color="#0a0e14",
        button_primary_text_color_dark="#0a0e14",
        block_background_fill="#161b22",
        block_background_fill_dark="#161b22",
        block_border_color="#29ddff22",
        block_border_color_dark="#29ddff22",
        block_label_background_fill="#1e293b",
        block_label_background_fill_dark="#1e293b",
        block_label_text_color="#29ddff",
        block_label_text_color_dark="#29ddff",
    )

    # Build the dashboard
    with gr.Blocks(
        title="vLLM Monitoring Dashboard",
        theme=kk_theme,
        css=custom_css,
    ) as dashboard:

        gr.Markdown("# vLLM Production Monitoring Dashboard")
        gr.Markdown("*InferenceIO - SmolLM-135M Inference Server*")

        # --- ROW 1: Live Status ---
        with gr.Row():
            with gr.Column(scale=1):
                status_text = gr.Textbox(
                    label="Server Status",
                    value="Checking...",
                    interactive=False,
                )
            with gr.Column(scale=1):
                live_tps = gr.Number(
                    label="Live Tokens/sec",
                    value=0,
                )
            with gr.Column(scale=1):
                live_latency = gr.Number(
                    label="Live Latency (s)",
                    value=0,
                )

        refresh_btn = gr.Button("Refresh Live Metrics", variant="primary", size="lg")

        def refresh_metrics():
            metrics = get_live_metrics()
            return (
                metrics["status"],
                metrics["tokens_per_second"],
                metrics["latency"],
            )

        refresh_btn.click(
            fn=refresh_metrics,
            outputs=[status_text, live_tps, live_latency],
        )

        gr.Markdown("")
        gr.Markdown("---")

        # --- ROW 2: Before/After Comparison ---
        gr.Markdown("## HuggingFace vs vLLM Comparison")
        gr.Markdown("")

        with gr.Row():
            with gr.Column(scale=1):
                gr.Plot(value=make_comparison_chart())
            with gr.Column(scale=1):
                gr.Markdown(f"""
### Performance Summary

| Metric | HuggingFace | vLLM |
|--------|-------------|------|
| Tokens/sec | {hf_tps:.1f} | {vllm_tps:.1f} |
| Improvement | - | {improvement:.1f}x |

**vLLM is {improvement:.1f}x faster** for single-request inference.
The advantage grows significantly under concurrent load.
""")

        gr.Markdown("")
        gr.Markdown("---")

        # --- ROW 3: Load Test Results ---
        if load_test_results:
            gr.Markdown("## Multi-User Load Test Results")
            gr.Markdown("")
            load_fig = make_load_chart()
            if load_fig:
                gr.Plot(value=load_fig)
            gr.Markdown("")
            gr.Markdown("---")

        # --- ROW 4: Tuning Results ---
        if tuning_results:
            gr.Markdown("## Parameter Tuning Results")
            gr.Markdown("")
            tuning_fig = make_tuning_chart()
            if tuning_fig:
                gr.Plot(value=tuning_fig)
            gr.Markdown("")
            gr.Markdown("---")

        # --- ROW 5: Lab Journey Summary ---
        gr.Markdown("## Lab Journey Summary")
        gr.Markdown(f"""
| Task | What You Did | Key Result |
|------|-------------|------------|
| 1 | HuggingFace baseline | {hf_tps:.1f} tok/s (single user) |
| 2 | vLLM offline inference | {vllm_tps:.1f} tok/s ({improvement:.1f}x faster) |
| 3 | KV cache simulation | ~80% memory waste with contiguous allocation |
| 4 | PagedAttention simulation | ~95% memory utilization with paging |
| 5 | OpenAI-compatible API | Server on port 8000 |
| 6 | Multi-user load test | Throughput scales with concurrent users |
| 7 | Parameter tuning | Optimized for workload |
| 8 | Monitoring dashboard | This dashboard! |
""")

        gr.Markdown("")

        gr.Markdown("""
### Key Takeaways

1. **Inference engines matter** — same model, different speeds
2. **KV cache is the bottleneck** — traditional systems waste 60-80% of memory
3. **PagedAttention solves it** — inspired by OS virtual memory paging
4. **vLLM scales** — throughput improves with concurrent users
5. **Production needs monitoring** — always track tokens/sec and latency
""")

        gr.Markdown("")
        gr.Markdown("---")
        gr.Markdown("**vLLM Monitoring Dashboard** — InferenceIO Production Monitoring")

    # Verify the live metrics path works before marking the task
    # complete - this catches an unfilled TODO 1, which would otherwise
    # be swallowed by get_live_metrics' error handling.
    print("\nTesting live metrics against the vLLM server...")
    metrics = get_live_metrics()
    if metrics["status"] != "healthy":
        print(f"\nERROR: Live metrics check failed: {metrics['status']}")
        print("Check TODO 1 in /root/code/task_8_dashboard.py and try again.")
        return

    # Create marker
    os.makedirs("/root/markers", exist_ok=True)
    with open("/root/markers/task8_complete.txt", "w") as f:
        f.write("TASK_8_COMPLETE\n")

    print("\nBuilding Gradio dashboard...")
    print("\nTask 8 Complete!")
    print("\nLaunching dashboard on port 7860...")
    print("Click the 'Gradio UI' button (top-right) to view the dashboard.")
    print("Press Ctrl+C to stop.\n")

    # Kill any existing process on port 7860
    import subprocess as _sp
    try:
        result = _sp.run(["ss", "-tlnp", "sport", "=", ":7860"], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if "pid=" in line:
                import re
                pids = re.findall(r'pid=(\d+)', line)
                for pid in pids:
                    try:
                        os.kill(int(pid), 9)
                        print(f"  Killed old process on port 7860 (PID {pid})")
                        time.sleep(1)
                    except ProcessLookupError:
                        pass
    except Exception:
        pass

    dashboard.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False,
    )


if __name__ == "__main__":
    main()
```

</details>


<details>
<summary><strong>8.1 결과</strong></summary>

### 8.1 결과
```sh
python task_8_dashboard.py 
=================================================================
Task 8: Production Monitoring Dashboard (Capstone)
=================================================================

Server: http://localhost:8000 (running)
Dashboard will be available at: http://localhost:7860
-----------------------------------------------------------------
/root/code/task_8_dashboard.py:266: DeprecationWarning: The 'theme' parameter in the Blocks constructor will be removed in Gradio 6.0. You will need to pass 'theme' to Blocks.launch() instead.
  with gr.Blocks(
/root/code/task_8_dashboard.py:266: DeprecationWarning: The 'css' parameter in the Blocks constructor will be removed in Gradio 6.0. You will need to pass 'css' to Blocks.launch() instead.
  with gr.Blocks(

Testing live metrics against the vLLM server...

Building Gradio dashboard...

Task 8 Complete!

Launching dashboard on port 7860...
Click the 'Gradio UI' button (top-right) to view the dashboard.
Press Ctrl+C to stop.

* Running on local URL:  http://0.0.0.0:7860
* To create a public link, set `share=True` in `launch()`.
```
</details>
