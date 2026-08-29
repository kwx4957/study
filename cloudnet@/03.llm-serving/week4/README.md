## LLM Serving 스터디 4주차

### 목차

- [1.환경 설정](#1-환경-설정)
- [2. vLLM 및 LM Cache 설치](2-vLLM-및-LM-Cache-설치)
- [3. LM Cache 동작 테스트](#3-lm-cache-동작-테스트)
- [4. LM Cache 실행 및 벤치](#4-lm-cache-실행-및-벤치)
  - [4.1 LM Cache bench bench test](#41-lm-cache-bench-bench-test)
- [5.](#5)
- [6. vllm이 LM Cache 사용한 경우와 사용하지 않은 경우 비교](#6-vllm이-lm-cache-사용한-경우와-사용하지-않은-경우-비교)
  - [6.1 LM Cache 비활성화 로그](#61-lm-cache-비활성화-로그)
  - [6.2 LM Cache 활성화 로그](#62-lm-cache-활성화-로그)
- [7. vllm 요청 테스트](#7-vllm-요청-테스트)
  - [7.1 LM Cache 비활성화](#71-lm-cache-비활성화)
  - [7.2 LM Cache 활성화](#72-lm-cache-활성화)
  - [7.3 결과 정리](#73-결과-정리)
- [8. python 요청 변경](#8-python-요청-변경)
  - [8.1 LM Cache 비활성화](#81-lm-cache-비활성화)
  - [8.2 LM Cache 활성화](#82-lm-cache-활성화)
  - [8.3 결과 정리](#83-결과-정리)

### 1. 환경 설정

- python3.12
- WSL(Rocky9)
- facebook/opt-125m

```sh
mkdir -p ~/projects-test
cd ~/projects-test

python3.12 -m venv .venv-lmcache
source .venv-lmcache/bin/activate

pip install -U pip wheel setuptools

git clone https://github.com/vllm-project/vllm.git
git clone https://github.com/LMCache/LMCache.git
```

### 2. vLLM 및 LM Cache 설치

가이드라인에서 권장하는 방식인 소스코드를 직접 빌드하려고 하였으나 너무 오랜 시간이 걸리고 지속적으로 OS 의존성(패키지) 누락으로 인한 빌드 실패로 인해 CI를 활용하여 설치를 진행했다.

```sh
# Official doc:
# https://docs.vllm.ai/en/stable/getting_started/installation/cpu/#apple-silicon

cd ~/projects-test/vllm

# Simplest usage (uses pip from the activated venv):
bash ~/projects-test/LMCache/.github/scripts/install_vllm_cpu.sh

# Or explicitly point to the venv's pip:
# PIP_BIN="~/projects-test/.venv-lmcache/bin/pip" \
#   bash ~/projects-test/LMCache/.github/scripts/install_vllm_cpu.sh
 
# If you need to pass extra pip args (e.g. mirror):
# PIP_INSTALL_EXTRA_ARGS="-i https://mirrors.tencent.com/pypi/simple" \
#   bash ~/projects-test/LMCache/.github/scripts/install_vllm_cpu.sh

# nvtx upstream sdist misses Cython as a build dep;
# install it manually on macOS first
pip install Cython openai 

# One-liner: install LMCache (skip GPU ext + GPU vendor deps)
NO_GPU_EXT=1 pip install --no-build-isolation -e ~/projects-test/LMCache
```


### 3. LM Cache 동작 테스트

LM Cache `0.5.5.dev36` 버전과 LM Cache가 cpu를 사용하게끔 설정된 것을 확인할수 있다.

```sh
python -c 'import lmcache; print(lmcache.__version__)'
#
LMCache INFO: torch_dev=StubCPUDevice(device_type=cpu), torch_device_type=cpu (_device_detect.py:312:lmcache.v1.platform._device_detect)
0.5.5.dev36

python -c \
  'from lmcache.integration.vllm.lmcache_mp_connector \
   import LMCacheMPConnector; print("connector OK")'
#
LMCache INFO: torch_dev=StubCPUDevice(device_type=cpu), torch_device_type=cpu (_device_detect.py:312:lmcache.v1.platform._device_detect)
Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
Triton is installed, but doesn't include CPU backend. Disabling Triton.
Triton not installed or not compatible; certain GPU-related functions will not be available.
LMCache INFO: multi_layer_block_kv_transfer mode: tensor (base.py:95:lmcache.v1.multiprocess.transfer_context.base)
connector OK
```

### 4. LM Cache 실행 및 벤치

이 챕터에서는 LM Cache가 동작하는지 검증과 LM Cache 설정 그리고 간단한 벤치를 수행한다. 벤치의 경우 `512 token`으로 3회 수행한다.

LM Cache 옵션
- --l1-size-gb 1 : L1 kv ccahe 용량을 최대 1GB 설정한다
- eviction-policy LR : kv cache가 꽉 차면 LRU 알고리즘으로 오래 사용되지 않은 캐시를 제거한다

```python
# Step 1: start LMCache server (background)
lmcache server \
  --port 5555 \
  --http-port 8080 \
  --l1-size-gb 1 \
  --eviction-policy LRU &

# Step 2: wait for healthcheck
while ! curl -fsS http://127.0.0.1:8080/healthcheck 2>/dev/null; do
  sleep 1
done
echo 'Server ready'

# Step 3: run bench (lmcache_driven mode)
lmcache bench server \
  --rpc-url tcp://127.0.0.1:5555 \
  --url http://127.0.0.1:8080 \
  --mode cpu \
  --transfer-mode lmcache_driven \
  --num-tokens 512 \
  --end 3

# Or with engine_driven mode:
# lmcache bench server \
#   --rpc-url tcp://127.0.0.1:5555 \
#   --url http://127.0.0.1:8080 \
#   --mode cpu \
#   --transfer-mode engine_driven \
#   --num-tokens 512 \
#   --end 3

# Stop the server when done:
kill %1
```

### 4.1 LM Cache bench bench test

 ```python
   [info] --transfer-mode=lmcache_driven on cpu mode: using REGISTER_KV_CACHE + STORE/RETRIEVE over POSIX SHM
 Connecting to LMCache MP Server at tcp://127.0.0.1:5555 (mode=cpu) ...
 Server chunk_size = 256
 Resolved KV shape spec: (2,1024,16,8,128):float16:32
 Each request: 513 tokens (2 full chunks)
 KV shape: 32 layers, 8 heads x 128, dtype=float16, blocks=1024x16, kv=2

 [rank 0] Allocated 32 CPU SHM tensors (prefix=/lmcache_kv_62532_r0)
  LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_TWO_NB_NH_BS_HS NL x [2, NB, NH, BS, HS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
  LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_TWO_NB_NH_BS_HS NL x [2, NB, NH, BS, HS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
  LMCache INFO: Group 0 first-layer tensor: layer_idx=0 shape=(2, 1024, 16, 8, 128) stride=(16777216, 16384, 1024, 128, 1) is_contiguous=True dtype=torch.float16 device=cpu storage_offset=0 numel=33554432 storage_nbytes=67108864 padding_per_block=0 (utils.py:603:lmcache.v1.gpu_connector.utils)
  LMCache INFO: group 0: compressed (tokens_per_block=16, slots_per_block=8) (kv_layer_groups.py:767:lmcache.v1.kv_layer_groups)
  LMCache INFO: KV layer groups: ---
 KernelGroupInfo(layers=32, indices=0-31, shape_desc=(kv=2, nl=32, nb=1024, bs=8, nh=16, hs=128, element_size=2, block_stride_elems=0), dtype=torch.float16, tokens_per_block=16, slots_per_block=8, engine_group_idx=0, sw_size_tokens=-1)
 --- (kv_layer_groups.py:474:lmcache.v1.kv_layer_groups)
  LMCache INFO: CPUCacheContext: 32 layers, 1024 blocks, dtype=torch.float16 (shm-backed) (cache_context.py:186:lmcache.v1.platform.cpu.cache_context)
  LMCache INFO: Registered KV cache for GPU ID 1000 with 32 layers (lmcache_driven_transfer.py:1010:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
 [rank 0] REGISTER_KV_CACHE: OK
 
 === Request seq=0 ===
   [seq 0/cold] LOOKUP: 0/2 chunks hit (1.6 ms)
  LMCache INFO: AffinityThreadPool: affinity_key=-5391682848642878554 assigned to worker slot 0 of 1 (thread affinity-pool-0-0); 1 distinct key(s) now bound (affinity_pool.py:108:lmcache.v1.multiprocess.affinity_pool)
  LMCache INFO: Stored 512 tokens in 0.163 seconds (lmcache_driven_transfer.py:1273:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 0/cold] STORE: stored (512 tokens, 163.9 ms, 1 writers)
 INFO:     127.0.0.1:51086 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 0/cold] CHECKSUM: dc71eaa56d6cdfb5 (2 chunks)
  LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.7 ms (external_request_id=req-0-warm, prefetch_request_id=-1) (storage_manager.py:726:lmcache.v1.distributed.storage_manager)
   [seq 0/warm] LOOKUP: 2/2 chunks hit (1.9 ms)
  LMCache INFO: Retrieved 512 tokens in 0.094 seconds (lmcache_driven_transfer.py:1515:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 0/warm] RETRIEVE: retrieved (512 tokens, 95.3 ms, 1 workers)
 INFO:     127.0.0.1:51090 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 0/warm] CHECKSUM: dc71eaa56d6cdfb5 (2 chunks)
   [seq 0] CHECKSUM MATCH OK
 
 === Request seq=1 ===
   [seq 1/cold] LOOKUP: 0/2 chunks hit (1.5 ms)
  LMCache INFO: Stored 512 tokens in 0.089 seconds (lmcache_driven_transfer.py:1273:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 1/cold] STORE: stored (512 tokens, 90.4 ms, 1 writers)
 INFO:     127.0.0.1:51098 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 1/cold] CHECKSUM: deef9de748d32e88 (2 chunks)
  LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.7 ms (external_request_id=req-1-warm, prefetch_request_id=-1) (storage_manager.py:726:lmcache.v1.distributed.storage_manager)
   [seq 1/warm] LOOKUP: 2/2 chunks hit (2.2 ms)
  LMCache INFO: Retrieved 512 tokens in 0.036 seconds (lmcache_driven_transfer.py:1515:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 1/warm] RETRIEVE: retrieved (512 tokens, 37.1 ms, 1 workers)
 INFO:     127.0.0.1:51114 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 1/warm] CHECKSUM: deef9de748d32e88 (2 chunks)
   [seq 1] CHECKSUM MATCH OK
 
 === Request seq=2 ===
   [seq 2/cold] LOOKUP: 0/2 chunks hit (2.0 ms)
  LMCache INFO: Stored 512 tokens in 0.075 seconds (lmcache_driven_transfer.py:1273:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 2/cold] STORE: stored (512 tokens, 76.5 ms, 1 writers)
 INFO:     127.0.0.1:51120 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 2/cold] CHECKSUM: 6fecbf59cb3d3a2e (2 chunks)
  LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.7 ms (external_request_id=req-2-warm, prefetch_request_id=-1) (storage_manager.py:726:lmcache.v1.distributed.storage_manager)
   [seq 2/warm] LOOKUP: 2/2 chunks hit (2.1 ms)
  LMCache INFO: Retrieved 512 tokens in 0.033 seconds (lmcache_driven_transfer.py:1515:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
   [seq 2/warm] RETRIEVE: retrieved (512 tokens, 33.6 ms, 1 workers)
 INFO:     127.0.0.1:51128 - "POST /cache/checksums HTTP/1.1" 200 OK
   [seq 2/warm] CHECKSUM: 6fecbf59cb3d3a2e (2 chunks)
   [seq 2] CHECKSUM MATCH OK
 
  LMCache INFO: Unregistered KV cache for GPU ID 1000 (lmcache_driven_transfer.py:1037:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
 [iid 1000] UNREGISTER_KV_CACHE: OK
 ===================== Server Bench Result ======================
 ------------------------ Configuration -------------------------
 RPC URL:                                    tcp://127.0.0.1:5555
 Mode:                                                        cpu
 Transfer mode:                                    lmcache_driven
 Tokens / request:                                            512
 Interval (s):                                               0.50
 --------------------------- Results ----------------------------
 Total requests:                                                3
 Checksum OK:                                                   3
 Checksum FAIL:                                                 0
 Pass rate (%):                                            100.00
 ----------------------- Cold Lookup (ms) -----------------------
 count:                                                         3
 mean:                                                       1.73
 min:                                                        1.53
 max:                                                        2.04
 p50:                                                        1.62
 p99:                                                        2.04
 ----------------------- Cold Store (ms) ------------------------
 count:                                                         3
 mean:                                                     110.25
 min:                                                       76.48
 max:                                                      163.86
 p50:                                                       90.40
 p99:                                                      163.86
 ----------------------- Warm Lookup (ms) -----------------------
 count:                                                         3
 mean:                                                       2.07
 min:                                                        1.85
 max:                                                        2.24
 p50:                                                        2.12
 p99:                                                        2.24
 ---------------------- Warm Retrieve (ms) ----------------------
 count:                                                         3
 mean:                                                      55.35
 min:                                                       33.57
 max:                                                       95.34
 p50:                                                       37.15
 p99:                                                       95.34
 ================================================================
 Done.
 ```

### 5. 

```python
# Memory budget for a 16 GB MacBook (safe defaults):
#   vLLM KV pool:         1 GB  (VLLM_CPU_KVCACHE_SPACE=1)
#   LMCache L1:           1 GB  (--l1-size-gb 1)
#   torch + model weights: ~1.5 GB
#   Python runtime:        ~0.5 GB
#   OS + apps:             ~6 GB
#   ------------------------------------------
#   Free headroom:         ~6 GB
 
# For an 8 GB MacBook, shrink everything:
#   VLLM_CPU_KVCACHE_SPACE=0.25
#   --l1-size-gb 0.5
#   --max-model-len 300
#   --max-num-seqs 1

# Terminal A: start LMCache server
source ~/projects-test/.venv-lmcache/bin/activate
 
lmcache server \
  --port 5555 \
  --http-port 8080 \
  --l1-size-gb 1 \
  --eviction-policy LRU
  
  
# Terminal B: start vLLM (macOS arm64)
source ~/projects-test/.venv-lmcache/bin/activate
 
# === CRITICAL: avoid vLLM OMP deadlock on macOS arm64 ===
export VLLM_CPU_OMP_THREADS_BIND=nobind
export OMP_NUM_THREADS=1
export KMP_BLOCKTIME=0
# ==========================================================
 
# CPU device + gloo rendezvous
export VLLM_DEVICE=cpu
export VLLM_CPU_KVCACHE_SPACE=1
export VLLM_HOST_IP=127.0.0.1
export GLOO_SOCKET_IFNAME=lo
 
# You can also set "lmcache.mp.mp_transfer_mode" to "engine_driven"
vllm serve facebook/opt-125m \
  --port 18000 \
  --dtype bfloat16 \
  --disable-hybrid-kv-cache-manager \
  --no-enable-prefix-caching \
  --max-model-len 2048 \
  --max-num-seqs 1 \
  --kv-transfer-config '{
    "kv_connector": "LMCacheMPConnector",
    "kv_role": "kv_both",
    "kv_connector_module_path":
        "lmcache.integration.vllm.lmcache_mp_connector",
    "kv_connector_extra_config": {
        "lmcache.mp.host": "tcp://localhost",
        "lmcache.mp.port": 5555,
"lmcache.mp.mp_transfer_mode": "lmcache_driven"
    }
  }'
  
# Terminal C: verify cache hit
source ~/projects-test/.venv-lmcache/bin/activate
 
cat > /tmp/test_lmcache_e2e.py <<'EOF'
import time, requests
URL = 'http://localhost:18000/v1/completions'
words = ['the','quick','brown','fox','jumps',
         'over','lazy','dog'] * 80   # ~640 tokens
prompt = ' '.join(words)
payload = dict(model='facebook/opt-125m', prompt=prompt,
               max_tokens=8, temperature=0.0)
for i in (1, 2):
    t0 = time.time()
    r = requests.post(URL, json=payload, timeout=600)
    print('round %d %d %.2fs' % (i, r.status_code, time.time()-t0),
          r.json()['usage'])
EOF
python /tmp/test_lmcache_e2e.py

round 1 200 0.34s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}
round 2 200 0.33s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}
```

### 6. vllm이 LM Cache 사용한 경우와 사용하지 않은 경우 비교 


1번 항목이 vllm이 LM CACHE를 사용하지 않고 실행, 2번 항목이 vllm이 LM CAHE를 활용하여 실행한 경우이다.
3번 항목은 별도의 터미널에서 LM Cache를 실행한다.

```bash
# 1) 터미널 A: LM Cache 비활성화, vllm 실행
vllm serve facebook/opt-125m \
  --port 18000 \
  --dtype bfloat16 \
  --disable-hybrid-kv-cache-manager \
  --no-enable-prefix-caching \
  --max-model-len 2048 \
  --max-num-seqs 1

# 2) 터미널 A: LM Cache 활용한 vllm 실행
vllm serve facebook/opt-125m \
  --port 18000 \
  --dtype bfloat16 \
  --disable-hybrid-kv-cache-manager \
  --no-enable-prefix-caching \
  --max-model-len 2048 \
  --max-num-seqs 1 \
  --kv-transfer-config '{
    "kv_connector": "LMCacheMPConnector",
    "kv_role": "kv_both",
    "kv_connector_module_path":
        "lmcache.integration.vllm.lmcache_mp_connector",
    "kv_connector_extra_config": {
        "lmcache.mp.host": "tcp://localhost",
        "lmcache.mp.port": 5555,
"lmcache.mp.mp_transfer_mode": "lmcache_driven"
    }
  }'

# 3) 터미널 B: LM CACEHE 실행
 lmcache server \
   --port 5555 \
   --http-port 8080 \
   --l1-size-gb 1 \
   --eviction-policy LRU
```

### 6.1 LM Cache 비활성화 로그
```bash
Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 16:45:33 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 16:45:33 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]        █     █     █▄   ▄█
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]  ▄▄ ▄█ █     █     █ ▀▄▀ █  version 0.28.1.dev202608260651
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]   █▄█▀ █     █     █     █  model   /root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]    ▀▀  ▀▀▀▀▀ ▀▀▀▀▀ ▀     ▀
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:347]
(APIServer pid=112750) INFO 08-28 16:45:50 [api_utils.py:286] non-default args: {'model_tag': '/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', 'port': 18000, 'model': '/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', 'dtype': 'bfloat16', 'max_model_len': 2048, 'enable_prefix_caching': False, 'max_num_seqs': 1, 'disable_hybrid_kv_cache_manager': True}
(APIServer pid=112750) WARNING 08-28 16:45:50 [envs.py:2239] Unknown vLLM environment variable detected: VLLM_DEVICE
(APIServer pid=112750) INFO 08-28 16:45:50 [model.py:684] Resolved architecture: OPTForCausalLM
(APIServer pid=112750) WARNING 08-28 16:45:50 [model.py:2355] Casting torch.float16 to torch.bfloat16.
(APIServer pid=112750) INFO 08-28 16:45:50 [model.py:2021] Using max model len 2048
(APIServer pid=112750) INFO 08-28 16:45:50 [kernel.py:365] Final IR op priority after setting platform defaults: IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native'])
(APIServer pid=112750) WARNING 08-28 16:45:50 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
INFO 08-28 16:47:19 [importing.py:60] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 16:47:19 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 16:47:19 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
(EngineCore pid=112825) INFO 08-28 16:47:32 [core.py:123] Initializing a V1 LLM engine (v0.28.1.dev202608260651) with config: model='/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', speculative_config=None, tokenizer='/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', skip_tokenizer_init=False, tokenizer_mode=auto, revision=None, tokenizer_revision=None, trust_remote_code=False, dtype=torch.bfloat16, max_seq_len=2048, download_dir=None, load_format=auto, tensor_parallel_size=1, pipeline_parallel_size=1, data_parallel_size=1, decode_context_parallel_size=1, dcp_comm_backend=ag_rs, disable_custom_all_reduce=True, quantization=None, quantization_config=None, enforce_eager=False, enable_return_routed_experts=False, kv_cache_dtype=auto, device_config=cpu, structured_outputs_config=StructuredOutputsConfig(backend='auto', disable_any_whitespace=False, disable_additional_properties=False, reasoning_parser='', reasoning_parser_plugin='', enable_in_reasoning=False), observability_config=ObservabilityConfig(show_hidden_metrics_for_version=None, otlp_traces_endpoint=None, collect_detailed_traces=None, per_request_spec_decode_metrics='none', kv_cache_metrics=False, kv_cache_metrics_sample=0.01, cudagraph_metrics=False, enable_layerwise_nvtx_tracing=False, enable_mfu_metrics=False, enable_mm_processor_stats=False, enable_logging_iteration_details=False, jit_monitor_mode='warn', jit_monitor_verbose=False), seed=0, served_model_name=/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6, enable_prefix_caching=False, enable_chunked_prefill=True, pooler_config=None, compilation_config={'mode': <CompilationMode.DYNAMO_TRACE_ONCE: 2>, 'debug_dump_path': None, 'cache_dir': '', 'compile_cache_save_format': 'binary', 'backend': 'inductor', 'custom_ops': ['none'], 'ir_enable_torch_wrap': False, 'splitting_ops': [], 'compile_mm_encoder': False, 'cudagraph_mm_encoder': False, 'encoder_cudagraph_token_budgets': [], 'encoder_cudagraph_max_vision_items_per_batch': 0, 'encoder_cudagraph_max_frames_per_batch': None, 'compile_sizes': None, 'compile_ranges_endpoints': [2048], 'inductor_compile_config': {'enable_auto_functionalized_v2': False, 'dce': True, 'size_asserts': False, 'nan_asserts': False, 'epilogue_fusion': True, 'cpp.dynamic_threads': True}, 'inductor_passes': {}, 'cudagraph_mode': <CUDAGraphMode.NONE: 0>, 'cudagraph_num_of_warmups': 0, 'cudagraph_capture_sizes': [], 'cudagraph_copy_inputs': False, 'cudagraph_specialize_lora': True, 'use_inductor_graph_partition': False, 'pass_config': {'fuse_norm_quant': False, 'fuse_act_quant': False, 'fuse_attn_quant': False, 'enable_sp': False, 'fuse_gemm_comms': False, 'fuse_allreduce_rms': False, 'enable_qk_norm_rope_fusion': False, 'fuse_rope_kvcache_cat_mla': False, 'fuse_act_padding': False, 'fuse_qk_norm_rope_kvcache': False}, 'max_cudagraph_capture_size': None, 'dynamic_shapes_config': {'type': <DynamicShapesType.BACKED: 'backed'>, 'evaluate_guards': False, 'assume_32_bit_indexing': False}, 'local_cache_dir': None, 'fast_moe_cold_start': False, 'static_all_moe_layers': []}, kernel_config=KernelConfig(ir_op_priority=IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native']), enable_flashinfer_autotune=True, enable_cutedsl_warmup=True, enable_jit_warmup=True, enable_bf16x3_router_gemm=False, moe_backend='auto', linear_backend='auto')
(EngineCore pid=112825) INFO 08-28 16:47:32 [multiproc_executor.py:153] DP group leader: node_rank=0, node_rank_within_dp=0, master_addr=127.0.0.1, mq_connect_ip=127.0.0.1 (local), world_size=1, local_world_size=1
(EngineCore pid=112825) INFO 08-28 16:47:32 [ompmultiprocessing.py:185] OpenMP thread binding info:
(EngineCore pid=112825) INFO 08-28 16:47:32 [ompmultiprocessing.py:185]         VLLM_CPU_OMP_THREADS_BIND='auto', auto_setup=True, skip_setup=False
(EngineCore pid=112825) INFO 08-28 16:47:32 [ompmultiprocessing.py:185]         local_world_size=1, reserve_cpu_num=1
(EngineCore pid=112825) INFO 08-28 16:47:32 [ompmultiprocessing.py:185]         local_rank=0, core ids=[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
(EngineCore pid=112825) INFO 08-28 16:47:32 [ompmultiprocessing.py:185]         reserved_cpus=[19]
INFO 08-28 16:48:37 [importing.py:60] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 16:48:37 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 16:48:37 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
WARNING 08-28 16:48:49 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
(Worker pid=112945) WARNING 08-28 16:48:49 [cpu_worker.py:127] libtcmalloc is not found in LD_PRELOAD. For best performance, please follow the section `set LD_PRELOAD` in https://docs.vllm.ai/en/latest/getting_started/installation/cpu/ to setup required pre-loaded libraries.
(Worker pid=112945) WARNING 08-28 16:48:49 [cpu_worker.py:127] libiomp is not found in LD_PRELOAD. For best performance, please follow the section `set LD_PRELOAD` in https://docs.vllm.ai/en/latest/getting_started/installation/cpu/ to setup required pre-loaded libraries.
(Worker pid=112945) INFO 08-28 16:48:49 [parallel_state.py:1638] world_size=1 rank=0 local_rank=0 distributed_init_method=file:///tmp/vllm_dist_2297b0ed49e84efdadc3c3c15f7fccf5 backend=gloo
(Worker pid=112945) INFO 08-28 16:48:50 [parallel_state.py:1982] rank 0 in world size 1 is assigned as DP rank 0, PP rank 0, PCP rank 0, TP rank 0, EP rank N/A, EPLB rank N/A
(Worker pid=112945) INFO 08-28 16:48:50 [cpu_model_runner.py:131] Starting to load model /root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6...
Loading pt checkpoint shards:   0% Completed | 0/1 [00:00<?, ?it/s]
Loading pt checkpoint shards: 100% Completed | 1/1 [00:01<00:00,  1.62s/it]
Loading pt checkpoint shards: 100% Completed | 1/1 [00:01<00:00,  1.62s/it]
(Worker pid=112945)
(Worker pid=112945) INFO 08-28 16:48:52 [default_loader.py:430] Loading weights took 1.62 seconds
(Worker pid=112945) WARNING 08-28 16:48:52 [utils.py:371] Failed to create oneDNN linear, fallback to torch linear. Exception: could not create a primitive descriptor for the matmul primitive. Run workload with environment variable ONEDNN_VERBOSE=all to get additional diagnostic information.
(EngineCore pid=112825) INFO 08-28 16:48:52 [torch_utils.py:277] Reducing Torch threads from 10 to 1 for serving. Set OMP_NUM_THREADS in the external environment to override.
(EngineCore pid=112825) INFO 08-28 16:48:52 [utils.py:305] Using LBHNC KV cache layout.
(Worker pid=112945) INFO 08-28 16:48:52 [cpu_model_runner.py:150] Warming up model for the compilation...
(Worker pid=112945) INFO 08-28 16:49:29 [decorators.py:710] saved AOT compiled function to /root/.cache/vllm/torch_compile_cache/torch_aot_compile/2e5fb44c8c080ff6c1d605a0e56d5e33ae78accc6f3d8e99b2b3daf75cf1fd0a/rank_0_0/model
(Worker pid=112945) INFO 08-28 16:49:32 [monitor.py:81] Initial profiling/warmup run took 2.87 s
(Worker pid=112945) INFO 08-28 16:49:33 [cpu_model_runner.py:154] Warming up done.
(Worker pid=112945) INFO 08-28 16:49:33 [cpu_worker.py:255] Explicitly set (1.0/15.51) GiB for KV cache on node 0.
(EngineCore pid=112825) INFO 08-28 16:49:33 [kv_cache_utils.py:1879] GPU KV cache size: 29,056 tokens, Maximum concurrency for 2,048 tokens per request: 14.19x
(EngineCore pid=112825) INFO 08-28 16:49:34 [core.py:368] init engine (profile, create kv cache, warmup model) took 41.93 s
(EngineCore pid=112825) WARNING 08-28 16:49:35 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
(EngineCore pid=112825) WARNING 08-28 16:49:35 [vllm.py:1420] Inductor compilation was disabled by user settings, optimizations settings that are only active during inductor compilation will be ignored.
(EngineCore pid=112825) INFO 08-28 16:49:35 [kernel.py:365] Final IR op priority after setting platform defaults: IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native'])
(APIServer pid=112750) INFO 08-28 16:49:35 [entry.py:135] Supported tasks: ['generate']
(APIServer pid=112750) INFO 08-28 16:49:36 [hf.py:547] Detected the chat template content format to be 'string'. You can set `--chat-template-content-format` to override this.
(APIServer pid=112750) INFO 08-28 16:49:36 [entry.py:139] Starting vLLM server on http://0.0.0.0:18000
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:61] Available routes are:
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /openapi.json, Methods: HEAD, GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /docs, Methods: HEAD, GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /docs/oauth2-redirect, Methods: HEAD, GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /redoc, Methods: HEAD, GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /load, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /version, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /health, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /metrics, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /tokenize, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /detokenize, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/models, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /ping, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /ping, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /invocations, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/chat/completions, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/chat/completions/batch, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/responses, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/responses/{response_id}, Methods: GET
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/responses/{response_id}/cancel, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/completions, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/messages, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/messages/count_tokens, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /generative_scoring, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /scale_elastic_ep, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /is_scaling_elastic_ep, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/chat/completions/render, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/messages/render, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/completions/render, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/chat/completions/derender, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /v1/completions/derender, Methods: POST
(APIServer pid=112750) INFO 08-28 16:49:36 [launcher.py:70] Route: /inference/v1/generate, Methods: POST
(APIServer pid=112750) INFO:     Started server process [112750]
(APIServer pid=112750) INFO:     Waiting for application startup.
(APIServer pid=112750) INFO:     Application startup complete.
```

### 6.2 LM Cache 활성화 로그
```bash
# LM Cache 로그 
[2026-08-28 17:01:18,476] LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_NB_NH_BS_CS NL x [NB, NH, BS, CS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
[2026-08-28 17:01:18,477] LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_NB_NH_BS_CS NL x [NB, NH, BS, CS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
[2026-08-28 17:01:18,477] LMCache INFO: Group 0 first-layer tensor: layer_idx=0 shape=(227, 12, 128, 128) stride=(196608, 16384, 128, 1) is_contiguous=True dtype=torch.bfloat16 device=cpu storage_offset=0 numel=44630016 storage_nbytes=1071120384 padding_per_block=0 (utils.py:603:lmcache.v1.gpu_connector.utils)
[2026-08-28 17:01:18,477] LMCache INFO: KV layer groups: ---
KernelGroupInfo(layers=12, indices=0-11, shape_desc=(kv=1, nl=12, nb=227, bs=128, nh=12, hs=128, element_size=2, block_stride_elems=0), dtype=torch.bfloat16, tokens_per_block=128, slots_per_block=128, engine_group_idx=0, sw_size_tokens=-1)
--- (kv_layer_groups.py:474:lmcache.v1.kv_layer_groups)
[2026-08-28 17:01:18,477] LMCache INFO: CPUCacheContext: 12 layers, 227 blocks, dtype=torch.bfloat16 (shm-backed) (cache_context.py:186:lmcache.v1.platform.cpu.cache_context)
[2026-08-28 17:01:18,478] LMCache INFO: Registered KV cache for GPU ID 2704798079673665322 with 12 layers (lmcache_driven_transfer.py:1010:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
```

```bash
INFO 08-28 16:57:34 [importing.py:60] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 16:57:34 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 16:57:34 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]        █     █     █▄   ▄█
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]  ▄▄ ▄█ █     █     █ ▀▄▀ █  version 0.28.1.dev202608260651
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]   █▄█▀ █     █     █     █  model   /root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]    ▀▀  ▀▀▀▀▀ ▀▀▀▀▀ ▀     ▀
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:347]
(APIServer pid=113327) INFO 08-28 16:57:55 [api_utils.py:286] non-default args: {'model_tag': '/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', 'port': 18000, 'model': '/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', 'dtype': 'bfloat16', 'max_model_len': 2048, 'served_model_name': ['facebook/opt-125m'], 'enable_prefix_caching': False, 'max_num_seqs': 1, 'disable_hybrid_kv_cache_manager': True, 'kv_transfer_config': KVTransferConfig(kv_connector='LMCacheMPConnector', engine_id='6c040150-6696-42b3-9e5f-715927849fb6', kv_buffer_device='cpu', kv_buffer_size=1000000000.0, kv_role='kv_both', kv_rank=None, kv_parallel_size=1, kv_ip='127.0.0.1', kv_port=14579, kv_connector_extra_config={'lmcache.mp.host': 'tcp://localhost', 'lmcache.mp.port': 5555, 'lmcache.mp.mp_transfer_mode': 'lmcache_driven'}, kv_connector_module_path='lmcache.integration.vllm.lmcache_mp_connector', enable_permute_local_kv=False, kv_load_failure_policy='fail')}
(APIServer pid=113327) WARNING 08-28 16:57:55 [envs.py:2239] Unknown vLLM environment variable detected: VLLM_DEVICE
(APIServer pid=113327) INFO 08-28 16:57:55 [model.py:684] Resolved architecture: OPTForCausalLM
(APIServer pid=113327) WARNING 08-28 16:57:55 [model.py:2355] Casting torch.float16 to torch.bfloat16.
(APIServer pid=113327) INFO 08-28 16:57:55 [model.py:2021] Using max model len 2048
(APIServer pid=113327) INFO 08-28 16:57:55 [kernel.py:365] Final IR op priority after setting platform defaults: IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native'])
(APIServer pid=113327) WARNING 08-28 16:57:56 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
INFO 08-28 16:59:12 [importing.py:60] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 16:59:12 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 16:59:12 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
(EngineCore pid=113410) INFO 08-28 16:59:24 [core.py:123] Initializing a V1 LLM engine (v0.28.1.dev202608260651) with config: model='/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', speculative_config=None, tokenizer='/root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6', skip_tokenizer_init=False, tokenizer_mode=auto, revision=None, tokenizer_revision=None, trust_remote_code=False, dtype=torch.bfloat16, max_seq_len=2048, download_dir=None, load_format=auto, tensor_parallel_size=1, pipeline_parallel_size=1, data_parallel_size=1, decode_context_parallel_size=1, dcp_comm_backend=ag_rs, disable_custom_all_reduce=True, quantization=None, quantization_config=None, enforce_eager=False, enable_return_routed_experts=False, kv_cache_dtype=auto, device_config=cpu, structured_outputs_config=StructuredOutputsConfig(backend='auto', disable_any_whitespace=False, disable_additional_properties=False, reasoning_parser='', reasoning_parser_plugin='', enable_in_reasoning=False), observability_config=ObservabilityConfig(show_hidden_metrics_for_version=None, otlp_traces_endpoint=None, collect_detailed_traces=None, per_request_spec_decode_metrics='none', kv_cache_metrics=False, kv_cache_metrics_sample=0.01, cudagraph_metrics=False, enable_layerwise_nvtx_tracing=False, enable_mfu_metrics=False, enable_mm_processor_stats=False, enable_logging_iteration_details=False, jit_monitor_mode='warn', jit_monitor_verbose=False), seed=0, served_model_name=facebook/opt-125m, enable_prefix_caching=False, enable_chunked_prefill=True, pooler_config=None, compilation_config={'mode': <CompilationMode.DYNAMO_TRACE_ONCE: 2>, 'debug_dump_path': None, 'cache_dir': '', 'compile_cache_save_format': 'binary', 'backend': 'inductor', 'custom_ops': ['none'], 'ir_enable_torch_wrap': False, 'splitting_ops': [], 'compile_mm_encoder': False, 'cudagraph_mm_encoder': False, 'encoder_cudagraph_token_budgets': [], 'encoder_cudagraph_max_vision_items_per_batch': 0, 'encoder_cudagraph_max_frames_per_batch': None, 'compile_sizes': None, 'compile_ranges_endpoints': [2048], 'inductor_compile_config': {'enable_auto_functionalized_v2': False, 'dce': True, 'size_asserts': False, 'nan_asserts': False, 'epilogue_fusion': True, 'cpp.dynamic_threads': True}, 'inductor_passes': {}, 'cudagraph_mode': <CUDAGraphMode.NONE: 0>, 'cudagraph_num_of_warmups': 0, 'cudagraph_capture_sizes': [], 'cudagraph_copy_inputs': False, 'cudagraph_specialize_lora': True, 'use_inductor_graph_partition': False, 'pass_config': {'fuse_norm_quant': False, 'fuse_act_quant': False, 'fuse_attn_quant': False, 'enable_sp': False, 'fuse_gemm_comms': False, 'fuse_allreduce_rms': False, 'enable_qk_norm_rope_fusion': False, 'fuse_rope_kvcache_cat_mla': False, 'fuse_act_padding': False, 'fuse_qk_norm_rope_kvcache': False}, 'max_cudagraph_capture_size': None, 'dynamic_shapes_config': {'type': <DynamicShapesType.BACKED: 'backed'>, 'evaluate_guards': False, 'assume_32_bit_indexing': False}, 'local_cache_dir': None, 'fast_moe_cold_start': False, 'static_all_moe_layers': []}, kernel_config=KernelConfig(ir_op_priority=IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native']), enable_flashinfer_autotune=True, enable_cutedsl_warmup=True, enable_jit_warmup=True, enable_bf16x3_router_gemm=False, moe_backend='auto', linear_backend='auto')
(EngineCore pid=113410) INFO 08-28 16:59:24 [multiproc_executor.py:153] DP group leader: node_rank=0, node_rank_within_dp=0, master_addr=127.0.0.1, mq_connect_ip=127.0.0.1 (local), world_size=1, local_world_size=1
(EngineCore pid=113410) INFO 08-28 16:59:24 [ompmultiprocessing.py:185] OpenMP thread binding info:
(EngineCore pid=113410) INFO 08-28 16:59:24 [ompmultiprocessing.py:185]         VLLM_CPU_OMP_THREADS_BIND='auto', auto_setup=True, skip_setup=False
(EngineCore pid=113410) INFO 08-28 16:59:24 [ompmultiprocessing.py:185]         local_world_size=1, reserve_cpu_num=2
(EngineCore pid=113410) INFO 08-28 16:59:24 [ompmultiprocessing.py:185]         local_rank=0, core ids=[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
(EngineCore pid=113410) INFO 08-28 16:59:24 [ompmultiprocessing.py:185]         reserved_cpus=[18, 19]
INFO 08-28 17:00:24 [importing.py:60] Triton is installed but 0 active driver(s) found (expected 1). Disabling Triton to prevent runtime errors.
WARNING 08-28 17:00:24 [importing.py:72] Triton is installed, but doesn't include CPU backend. Disabling Triton.
INFO 08-28 17:00:24 [importing.py:95] Triton not installed or not compatible; certain GPU-related functions will not be available.
WARNING 08-28 17:00:37 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
(Worker pid=113483) WARNING 08-28 17:00:37 [cpu_worker.py:127] libtcmalloc is not found in LD_PRELOAD. For best performance, please follow the section `set LD_PRELOAD` in https://docs.vllm.ai/en/latest/getting_started/installation/cpu/ to setup required pre-loaded libraries.
(Worker pid=113483) WARNING 08-28 17:00:37 [cpu_worker.py:127] libiomp is not found in LD_PRELOAD. For best performance, please follow the section `set LD_PRELOAD` in https://docs.vllm.ai/en/latest/getting_started/installation/cpu/ to setup required pre-loaded libraries.
(Worker pid=113483) INFO 08-28 17:00:37 [parallel_state.py:1638] world_size=1 rank=0 local_rank=0 distributed_init_method=file:///tmp/vllm_dist_f9ede3d08e2a481eaa563a53686817e2 backend=gloo
(Worker pid=113483) INFO 08-28 17:00:37 [parallel_state.py:1982] rank 0 in world size 1 is assigned as DP rank 0, PP rank 0, PCP rank 0, TP rank 0, EP rank N/A, EPLB rank N/A
(Worker pid=113483) INFO 08-28 17:00:37 [cpu_model_runner.py:131] Starting to load model /root/.cache/huggingface/hub/models--facebook--opt-125m/snapshots/27dcfa74d334bc871f3234de431e71c6eeba5dd6...
Loading pt checkpoint shards:   0% Completed | 0/1 [00:00<?, ?it/s]
Loading pt checkpoint shards: 100% Completed | 1/1 [00:00<00:00,  3.71it/s]
Loading pt checkpoint shards: 100% Completed | 1/1 [00:00<00:00,  3.71it/s]
(Worker pid=113483)
(Worker pid=113483) INFO 08-28 17:00:37 [default_loader.py:430] Loading weights took 0.27 seconds
(Worker pid=113483) WARNING 08-28 17:00:37 [utils.py:371] Failed to create oneDNN linear, fallback to torch linear. Exception: could not create a primitive descriptor for the matmul primitive. Run workload with environment variable ONEDNN_VERBOSE=all to get additional diagnostic information.
(EngineCore pid=113410) INFO 08-28 17:00:37 [torch_utils.py:277] Reducing Torch threads from 10 to 1 for serving. Set OMP_NUM_THREADS in the external environment to override.
(EngineCore pid=113410) [2026-08-28 17:00:39,562] LMCache INFO: torch_dev=StubCPUDevice(device_type=cpu), torch_device_type=cpu (_device_detect.py:312:lmcache.v1.platform._device_detect)
(EngineCore pid=113410) [2026-08-28 17:00:40,170] LMCache INFO: multi_layer_block_kv_transfer mode: tensor (base.py:95:lmcache.v1.multiprocess.transfer_context.base)
(EngineCore pid=113410) INFO 08-28 17:00:40 [utils.py:305] Using LBHNC KV cache layout.
(Worker pid=113483) INFO 08-28 17:00:40 [cpu_model_runner.py:150] Warming up model for the compilation...
(Worker pid=113483) INFO 08-28 17:01:12 [decorators.py:710] saved AOT compiled function to /root/.cache/vllm/torch_compile_cache/torch_aot_compile/7e4957a3e5a3e0754834d75fe3e65462c9b19029b96abc32696cbf9442e03499/rank_0_0/model
(Worker pid=113483) INFO 08-28 17:01:15 [monitor.py:81] Initial profiling/warmup run took 2.80 s
(Worker pid=113483) INFO 08-28 17:01:16 [cpu_model_runner.py:154] Warming up done.
(Worker pid=113483) INFO 08-28 17:01:16 [cpu_worker.py:255] Explicitly set (1.0/15.51) GiB for KV cache on node 0.
(EngineCore pid=113410) INFO 08-28 17:01:16 [kv_cache_utils.py:1879] GPU KV cache size: 29,056 tokens, Maximum concurrency for 2,048 tokens per request: 14.19x
(Worker pid=113483) [2026-08-28 17:01:17,605] LMCache INFO: torch_dev=StubCPUDevice(device_type=cpu), torch_device_type=cpu (_device_detect.py:312:lmcache.v1.platform._device_detect)
(Worker pid=113483) [2026-08-28 17:01:18,048] LMCache INFO: multi_layer_block_kv_transfer mode: tensor (base.py:95:lmcache.v1.multiprocess.transfer_context.base)
(Worker pid=113483) INFO 08-28 17:01:18 [factory.py:62] Creating v1 connector with name: LMCacheMPConnector and engine_id: 6c040150-6696-42b3-9e5f-715927849fb6
(Worker pid=113483) WARNING 08-28 17:01:18 [base.py:203] Initializing KVConnectorBase_V1. This API is experimental and subject to change in the future as we iterate the design.
(Worker pid=113483) [2026-08-28 17:01:18,119] LMCache INFO: lmcache.mp.mq_timeout = 300.0 (vllm_multi_process_adapter.py:125:lmcache.integration.vllm.vllm_multi_process_adapter)
(Worker pid=113483) [2026-08-28 17:01:18,119] LMCache INFO: lmcache.mp.heartbeat_interval = 10.0 (vllm_multi_process_adapter.py:125:lmcache.integration.vllm.vllm_multi_process_adapter)
(Worker pid=113483) [2026-08-28 17:01:18,119] LMCache INFO: lmcache.mp.mp_transfer_mode = lmcache_driven (overridden, default: auto) (vllm_multi_process_adapter.py:117:lmcache.integration.vllm.vllm_multi_process_adapter)
(Worker pid=113483) [2026-08-28 17:01:18,119] LMCache INFO: LMCache MP worker adapter created with instance_id=2704798079673665322 (vllm_multi_process_adapter.py:1137:lmcache.integration.vllm.vllm_multi_process_adapter)
(Worker pid=113483) [2026-08-28 17:01:18,268] LMCache INFO: Registering kv caches! (lmcache_mp_connector.py:529:lmcache.integration.vllm.lmcache_mp_connector)
(Worker pid=113483) [2026-08-28 17:01:18,268] LMCache ERROR: vLLM is not available but tried to query kv cache layout information, cannot get KV cache layout (utils.py:68:lmcache.integration.vllm.utils)
(Worker pid=113483) [2026-08-28 17:01:18,268] LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_NB_NH_BS_CS NL x [NB, NH, BS, CS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
(Worker pid=113483) [2026-08-28 17:01:18,268] LMCache INFO: Engine KV Format: EngineKVFormat.NL_X_NB_NH_BS_CS NL x [NB, NH, BS, CS] (detection.py:69:lmcache.v1.gpu_connector.kv_format.detection)
(Worker pid=113483) [2026-08-28 17:01:18,268] LMCache INFO: Registering kv caches (vllm_multi_process_adapter.py:1296:lmcache.integration.vllm.vllm_multi_process_adapter)
(Worker pid=113483) [2026-08-28 17:01:18,269] LMCache INFO: Creating transfer context (device_type=cpu, mode=lmcache_driven) (worker_transfer.py:879:lmcache.v1.multiprocess.transfer_context.worker_transfer)
(Worker pid=113483) [2026-08-28 17:01:18,279] LMCache ERROR: vLLM is not available but tried to query kv cache layout information, cannot get KV cache layout (utils.py:68:lmcache.integration.vllm.utils)
(Worker pid=113483) [2026-08-28 17:01:18,279] LMCache INFO: Wrapping 12 KV cache tensors for IPC (kv_wrap.py:62:lmcache.v1.platform.kv_wrap)
(Worker pid=113483) [2026-08-28 17:01:18,456] LMCache INFO: Migrated CPU KV backing storage (segment_nbytes=1071120384, view_offset=0) to SHM /lmcache_kv_113483_0 (shm.py:411:lmcache.v1.platform.cpu.shm)
(EngineCore pid=113410) INFO 08-28 17:01:18 [core.py:368] init engine (profile, create kv cache, warmup model) took 40.67 s
(EngineCore pid=113410) INFO 08-28 17:01:20 [factory.py:62] Creating v1 connector with name: LMCacheMPConnector and engine_id: 6c040150-6696-42b3-9e5f-715927849fb6
(EngineCore pid=113410) WARNING 08-28 17:01:20 [base.py:203] Initializing KVConnectorBase_V1. This API is experimental and subject to change in the future as we iterate the design.
(EngineCore pid=113410)
(EngineCore pid=113410)  _     __  __    ____           _
(EngineCore pid=113410) | |   |  \/  |  / ___|__ _  ___| |__   ___      LMCache v0.5.5.dev36 (g4133a277)
(EngineCore pid=113410) | |   | |\/| | | |   / _` |/ __| '_ \ / _ \     Website:  https://lmcache.ai/
(EngineCore pid=113410) | |___| |  | | | |__| (_| | (__| | | |  __/     Recipes:  https://docs.lmcache.ai/recipes
(EngineCore pid=113410) |_____|_|  |_|  \____\__,_|\___|_| |_|\___|     LinkedIn: https://www.linkedin.com/company/lmcache-lab
(EngineCore pid=113410) Set LMCACHE_DISABLE_BANNER=1 to hide this banner.
(EngineCore pid=113410)
(EngineCore pid=113410) [2026-08-28 17:01:20,827] LMCache INFO: lmcache.mp.mq_timeout = 300.0 (vllm_multi_process_adapter.py:125:lmcache.integration.vllm.vllm_multi_process_adapter)
(EngineCore pid=113410) [2026-08-28 17:01:20,827] LMCache INFO: lmcache.mp.heartbeat_interval = 10.0 (vllm_multi_process_adapter.py:125:lmcache.integration.vllm.vllm_multi_process_adapter)
(EngineCore pid=113410) [2026-08-28 17:01:20,827] LMCache INFO: lmcache.mp.mp_transfer_mode = lmcache_driven (overridden, default: auto) (vllm_multi_process_adapter.py:117:lmcache.integration.vllm.vllm_multi_process_adapter)
(EngineCore pid=113410) [2026-08-28 17:01:20,828] LMCache INFO: Bind GPU block pool in LMCacheMPConnector scheduler (lmcache_mp_connector.py:776:lmcache.integration.vllm.lmcache_mp_connector)
(EngineCore pid=113410) WARNING 08-28 17:01:20 [vllm.py:681] Model Runner V2 requires Triton; using the V1 model runner instead.
(EngineCore pid=113410) WARNING 08-28 17:01:21 [vllm.py:1420] Inductor compilation was disabled by user settings, optimizations settings that are only active during inductor compilation will be ignored.
(EngineCore pid=113410) INFO 08-28 17:01:21 [kernel.py:365] Final IR op priority after setting platform defaults: IrOpPriorityConfig(rms_norm=['native'], fused_add_rms_norm=['native'])
(APIServer pid=113327) [2026-08-28 17:01:22,270] LMCache INFO: torch_dev=StubCPUDevice(device_type=cpu), torch_device_type=cpu (_device_detect.py:312:lmcache.v1.platform._device_detect)
(APIServer pid=113327) [2026-08-28 17:01:23,112] LMCache INFO: multi_layer_block_kv_transfer mode: tensor (base.py:95:lmcache.v1.multiprocess.transfer_context.base)
(APIServer pid=113327) INFO 08-28 17:01:23 [entry.py:135] Supported tasks: ['generate']
(APIServer pid=113327) INFO 08-28 17:01:23 [hf.py:547] Detected the chat template content format to be 'string'. You can set `--chat-template-content-format` to override this.
(APIServer pid=113327) INFO 08-28 17:01:23 [entry.py:139] Starting vLLM server on http://0.0.0.0:18000
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:61] Available routes are:
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /openapi.json, Methods: HEAD, GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /docs, Methods: HEAD, GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /docs/oauth2-redirect, Methods: HEAD, GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /redoc, Methods: HEAD, GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /load, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /version, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /health, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /metrics, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /tokenize, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /detokenize, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/models, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /ping, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /ping, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /invocations, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/chat/completions, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/chat/completions/batch, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/responses, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/responses/{response_id}, Methods: GET
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/responses/{response_id}/cancel, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/completions, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/messages, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/messages/count_tokens, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /generative_scoring, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /scale_elastic_ep, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /is_scaling_elastic_ep, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/chat/completions/render, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/messages/render, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/completions/render, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/chat/completions/derender, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /v1/completions/derender, Methods: POST
(APIServer pid=113327) INFO 08-28 17:01:23 [launcher.py:70] Route: /inference/v1/generate, Methods: POST
(APIServer pid=113327) INFO:     Started server process [113327]
(APIServer pid=113327) INFO:     Waiting for application startup.
(APIServer pid=113327) INFO:     Application startup complete.
```

### 7. vllm 요청 테스트 

요청을 보내기 앞서, 주의할 점은 vllm을 종료하더라도 LM Cache가 실행중이라면 kv cache를 저장하고 있다. 이를 초기화하기 위해서는 LM Cacehe에 캐시를 초기화하는 요청을 보내야한다. 

> curl -X POST http://localhost:8080/cache/clear
> {"status":"ok","cleared":{"tier":"l1"}

테스트 환경
- prefix 캐싱 비활성화
- 최대 토큰 2048
- 최대 동시 처리 1개

```sh
# 터미널 C: verify cache hit
source ~/projects-test/.venv-lmcache/bin/activate

cat > /tmp/test_lmcache_e2e.py <<'EOF'
import time
import requests
import statistics

URL = "http://localhost:18000/v1/completions"

words = [
    "the", "quick", "brown", "fox",
    "jumps", "over", "lazy", "dog"
] * 80

prompt = " ".join(words)

payload = {
    "model": "facebook/opt-125m",
    "prompt": prompt,
    "max_tokens": 8,
    "temperature": 0.0,
}

results = []

for i in range(20):
    start = time.perf_counter()

    r = requests.post(
        URL,
        json=payload,
        timeout=600,
    )

    elapsed = time.perf_counter() - start

    print(
        f"round {i+1}: "
        f"{elapsed:.3f}s "
        f"{r.json()['usage']}"
    )

    if i > 0:
        results.append(elapsed)

print()
print("avg :", statistics.mean(results))
print("p50 :", statistics.median(results))
print("min :", min(results))
print("max :", max(results))
EOF

python3.12 /tmp/test_lmcache_e2e.py
```

### 7.1 LM Cache 비활성화
```sh
# 1) curl 요청 결과. 총 20개 요청
python3.12 /tmp/test_lmcache_e2e.py
round 1: 1.296s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}
...
round 20: 1.073s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}

avg : 1.0693721517362926
p50 : 1.0711494029965252
min : 1.049135113004013
max : 1.0981412420078414

# 2) vllm 로그
Engine 000: Avg prompt throughput: 448.7 tokens/s, Avg generation throughput: 5.6 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%
Engine 000: Avg prompt throughput: 576.9 tokens/s, Avg generation throughput: 7.2 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%
Engine 000: Avg prompt throughput: 256.4 tokens/s, Avg generation throughput: 3.2 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%
Engine 000: Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%
```

### 7.2 LM Cache 활성화
```sh
# 1) curl 요청 결과. 총 20개 요청
round 1: 1.364s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}
round 2: 1.104s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}
...
round 20: 0.338s {'prompt_tokens': 641, 'total_tokens': 649, 'completion_tokens': 8, 'prompt_tokens_details': None, 'completion_tokens_details': None}

avg : 0.364730112789211
p50 : 0.3063301640067948
min : 0.30022546400141437
max : 1.1042040130123496

# 2) vllm 로그
LMCache INFO: PeriodicThread lmcache-heartbeat entering main loop (interval=10.0s) (periodic_thread.py:304:lmcache.v1.periodic_thread)
LMCache INFO: Started PeriodicThread: lmcache-heartbeat (level=critical, interval=10.0s, init_wait=0.0s) (periodic_thread.py:248:lmcache.v1.periodic_thread)
Engine 000: Avg prompt throughput: 360.4 tokens/s, Avg generation throughput: 16.0 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%, External prefix cache hit rate: 71.9%
Engine 000: Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Waiting: 0 reqs, GPU KV cache usage: 0.0%, Prefix cache hit rate: 0.0%, External prefix cache hit rate: 71.9%

# 3) LM Cache 로그
LMCache INFO: AffinityThreadPool: affinity_key=7757079394529801316 assigned to worker slot 0 of 1 (thread affinity-pool-0-0); 1 distinct key(s) now bound (affinity_pool.py:108:lmcache.v1.multiprocess.affinity_pool)

# 3-1) 첫 요청
LMCache INFO: Stored 512 tokens in 0.134 seconds (lmcache_driven_transfer.py:1273:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.5 ms (external_request_id=cmpl-9d8932e27aeae1af-0-802d0cde, prefetch_request_id=-1)

# 3-2) 2번 요청
LMCache INFO: Retrieved 512 tokens in 0.009 seconds (lmcache_driven_transfer.py:1515:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.6 ms (external_request_id=cmpl-84207609a329e1f8-0-99db0914, prefetch_request_id=-1)

# 3-3) 20번째 마지막 요청
LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2) in 0.6 ms (external_request_id=cmpl-abcae9acf4f526d2-0-9e9c71a8, prefetch_request_id=-1)  
LMCache INFO: Retrieved 512 tokens in 0.005 seconds (lmcache_driven_transfer.py:1515:lmcache.v1.multiprocess.modules.lmcache_driven_transfer)
```

### 7.3 결과 정리
LM Cache가 641개의 토큰 중 512개 토큰의 kv cache를 L1에 저장하여 활용중이다. 첫 저장은 `0.134s`가 걸린 이후 조회에는 `0.009s`로 상당한 성능차이가 있음을 알수 있다.

| 지표         | LMCache 비활성화 | LMCache 활성화 |             개선 |
| ---------- | -----------: | ----------: | -------------: |
| 평균 응답시간    |       1.069s |  **0.365s** | **약 65.9% 감소** |
| P50        |       1.071s |  **0.306s** | **약 71.4% 감소** |
| 최소         |       1.049s |  **0.300s** | **약 71.4% 감소** |
| 최대         |       1.098s |      1.104s |       초기 요청 영향 |
| Prompt     |   641 tokens |  641 tokens |             동일 |
| Completion |     8 tokens |    8 tokens |             동일 |



### 8. python 요청 변경 

```python
from openai import OpenAI

import argparse
import contextlib
import os
import time
from dataclasses import asdict

#from lmcache.experimental.cache_engine import LMCacheEngineBuilder
#from lmcache.integration.vllm.utils import ENGINE_NAME

from vllm import LLM, SamplingParams
from vllm.config import KVTransferConfig
from vllm.engine.arg_utils import EngineArgs

# Modify OpenAI's API key and API base to use vLLM's API server.
model_id="facebook/opt-125m"
openai_api_key = "EMPTY"
openai_api_base = "http://localhost:18000/v1"
client = OpenAI(
    api_key=openai_api_key,
    base_url=openai_api_base,
)

sampling_params = SamplingParams(temperature=0,
                                 top_p=0.95,
                                 max_tokens=10)

def print_output_online(
    client,
    prompt: list[str],
    sampling_params: SamplingParams,
    req_str: str,
):
    # Should be able to see logs like the following:
    # `LMCache INFO: Storing KV cache for 6006 out of 6006 tokens for request 0`
    # This indicates that the KV cache has been stored in LMCache.
    start = time.time()
    completion = client.completions.create(model=model_id,
                                              prompt=prompt)
    print("Completion result:", completion)
    print("-" * 50)
    # for output in outputs:
    #     generated_text = output.outputs[0].text
    #     print(f"Generated text: {generated_text!r}")
    time_elapsed = time.time() - start
    print(f"Generation took {time_elapsed:.2f} seconds, "
          f"{req_str} request done.")
    print("-" * 50)
    return time_elapsed

time_cold_lmcache = []
for i in range(30)[::-1]:
    print('First time', i)
    shared_prompt = f"Hello this is now a brand new prompt, how are you? {i}"
    auto_prompt = shared_prompt*50+ "Hello, my name is"

    time_cold_lmcache.append(print_output_online(client, auto_prompt, sampling_params, "auto"))

time_warm_lmcache = []
for i in range(30):
    print('Second time', i)
    shared_prompt = f"Hello this is now a brand new prompt, how are you? {i}"
    auto_prompt = shared_prompt*50+ "Hello, my name is"

    time_warm_lmcache.append(print_output_online(client, auto_prompt, sampling_params, "auto"))
```

### 8.1 LM Cache 비활성화


### 8.2 LM Cache 활성화


### 8.3 결과 정리

## 1. 결론 요약

동일한 706-token 프롬프트를 반복 요청한 로그를 비교한 결과, **LMCache가 활성화되고 캐시가 준비된 Warm 구간의 평균 응답시간은 0.521초**, LMCache 미사용의 대응 구간은 **1.441초**였다.

- 평균 응답시간 감소: **0.920초/요청**
- 지연시간 개선율: **63.9%**
- 처리 속도 배수: **2.77배**
- 30회 누적시간: **43.23초 → 15.62초** (총 **27.61초 절감**)

LMCache 서버 로그에서도 Cold 구간에 30회 저장, Warm 구간에 30회 조회가 확인됐다. Warm 요청마다 512 tokens가 L1에서 복원됐으며, 조회 자체는 평균 0.0053초였다. 따라서 이번 실험에서는 LMCache가 긴 프롬프트의 prefill 계산 일부를 재사용해 응답시간을 크게 줄였다고 판단할 수 있다.

## 2. 분석 대상

| 파일 | 역할 | 확인 내용 |
|---|---|---|
| `Python_LM_Cache_active_output.md` | LMCache ON 클라이언트 로그 | Cold 30회, Warm 30회 응답시간 |
| `Python_LM_Cache_deactive_output.md` | LMCache OFF 클라이언트 로그 | 동일 구성의 2개 구간, 총 60회 응답시간 |
| `LM_Cache_output.md` | LMCache 서버 로그 | 512-token 저장 30회, 조회 30회 및 소요시간 |
| `vllm_LM_Cache_active_output.md` | LMCache ON vLLM 로그 | HTTP 200 60회, external cache hit 지표 |
| `vllm_LM_Cache_deactive_output.md` | LMCache OFF vLLM 로그 | HTTP 200 60회, external cache 지표 없음 |

모든 Python 응답에서 모델은 `facebook/opt-125m`, 입력은 706 tokens, 출력은 16 tokens였다. 두 실행 모두 `/v1/completions` 요청 60회가 HTTP 200으로 완료됐다.

## 3. 비교 방법

Python 로그의 다음 값을 요청별 end-to-end 응답시간으로 사용했다.

```text
Generation took N.NN seconds, auto request done.
```

LMCache ON 실행은 첫 30회가 서로 다른 프롬프트를 처음 처리하는 Cold/Store 구간이고, 다음 30회가 같은 프롬프트를 다시 처리하는 Warm/Retrieve 구간이다. LMCache OFF 실행도 동일하게 두 번째 30회를 대응 구간으로 사용했다.

계산식은 다음과 같다.

```text
평균 = 요청시간 합계 / 요청 수
개선율(%) = (OFF 평균 - ON Warm 평균) / OFF 평균 × 100
속도 배수 = OFF 평균 / ON Warm 평균
```

## 4. Python 응답시간 결과

| 조건 | 요청 수 | 평균 | 중앙값 | 최소 | 최대 | 합계 |
|---|---:|---:|---:|---:|---:|---:|
| LMCache ON — Cold 전체 | 30 | 1.445초 | 1.300초 | 1.220초 | 5.520초 | 43.34초 |
| LMCache ON — Cold 안정 구간¹ | 29 | 1.304초 | 1.300초 | 1.220초 | 1.400초 | 37.82초 |
| **LMCache ON — Warm** | **30** | **0.521초** | **0.520초** | **0.500초** | **0.560초** | **15.62초** |
| LMCache OFF — 1차 전체 | 30 | 1.498초 | 1.350초 | 1.210초 | 5.770초 | 44.95초 |
| LMCache OFF — 1차 안정 구간¹ | 29 | 1.351초 | 1.350초 | 1.210초 | 1.500초 | 39.18초 |
| **LMCache OFF — 2차** | **30** | **1.441초** | **1.415초** | **1.350초** | **1.600초** | **43.23초** |

¹ 각 실행의 첫 요청은 서버/모델 초기화 영향으로 각각 5.52초와 5.77초가 걸려, 정상 반복 요청보다 약 4배 느렸다. 안정 구간은 이 첫 요청을 제외한 값이다.

### 핵심 A/B 계산

```text
응답시간 절감 = 1.441 - 0.5207
              = 0.9203초/요청

개선율 = (1.441 - 0.5207) / 1.441 × 100
       = 63.87%

속도 배수 = 1.441 / 0.5207
          = 2.77배

30회 누적 절감 = 43.23 - 15.62
               = 27.61초
```

LMCache ON 실행 내부에서도 초기화 요청을 제외한 Cold 평균 1.304초와 Warm 평균 0.521초를 비교하면 **60.1% 감소, 2.50배 향상**이다. 독립적인 OFF 실행과의 비교뿐 아니라 같은 프로세스 안의 Cold/Warm 비교에서도 효과가 일관되게 나타났다.

## 5. LMCache 동작 근거

LMCache 서버 로그의 Cold 구간에는 다음 형태의 저장 기록이 30회 존재한다.

```text
LMCache INFO: Stored 512 tokens in 0.017 seconds
```

Warm 구간에는 다음 형태의 조회 기록이 30회 존재한다.

```text
LMCache INFO: Prefetch request completed (L1+L2): 2/2 retained keys (2 L1, 0 L2)
LMCache INFO: Retrieved 512 tokens in 0.005 seconds
```

| LMCache 작업 | 횟수 | 평균 | 중앙값 | 최소 | 최대 | 합계 |
|---|---:|---:|---:|---:|---:|---:|
| 512 tokens 저장 | 30 | 0.0584초 | 0.0175초 | 0.012초 | 0.287초 | 1.751초 |
| 512 tokens 조회 | 30 | 0.0053초 | 0.0050초 | 0.004초 | 0.011초 | 0.160초 |

조회는 저장보다 평균 약 **10.94배 빠르다**. 입력 706 tokens 중 로그상 512 tokens를 복원했으므로, 요청 단위의 단순 비율은 다음과 같다.

```text
512 / 706 × 100 = 72.5%
```

이는 프롬프트 전체가 아니라 캐시 블록 경계에 맞는 512 tokens가 재사용됐음을 뜻한다. 나머지 토큰과 decode 16 tokens는 계속 처리해야 하므로, 응답시간이 72.5%가 아니라 63.9% 감소한 것은 자연스럽다.

## 6. vLLM 로그 교차 검증

LMCache ON 로그에는 vLLM 자체 prefix cache가 0.0%인 동시에 external cache 지표가 나타난다.

```text
Prefix cache hit rate: 0.0%, External prefix cache hit rate: 61.7%
...
Prefix cache hit rate: 0.0%, External prefix cache hit rate: 44.5%
```

반면 LMCache OFF 로그에는 모든 측정 구간에서 다음 항목만 있고 `External prefix cache hit rate`는 없다.

```text
Prefix cache hit rate: 0.0%
```

따라서 성능 향상이 vLLM 내장 prefix caching 때문이 아니라 LMCache external KV cache 경로에서 발생했다는 근거가 된다. ON 로그의 external hit rate는 Cold와 Warm 요청이 섞인 누적/구간 지표이므로, 개별 Warm 요청의 `512 / 706`과 숫자가 정확히 같을 필요는 없다.

vLLM의 `Avg prompt throughput`은 10초 단위 구간값이며 요청 도착 시점과 Cold/Warm이 섞여 있다. 그러므로 본 보고서의 핵심 A/B 지표로는 요청별 end-to-end 시간과 LMCache의 실제 Store/Retrieve 기록을 사용했다.

## 7. 해석 및 한계

이번 로그로 확인되는 결론은 명확하다. **동일 프롬프트가 반복되는 단일 요청 환경에서는 LMCache Warm hit이 평균 응답시간을 약 64% 줄였다.** 또한 모든 요청이 HTTP 200으로 완료돼 성능 개선 과정에서 요청 실패가 관찰되지 않았다.

다만 다음 한계가 있다.

- 측정값은 0.01초 단위로 출력되어 세밀한 백분위수 분석에는 한계가 있다.
- 두 조건은 서로 다른 시간대와 서버 프로세스에서 실행됐으므로 완전히 동일한 시스템 부하가 보장되지는 않는다.
- 첫 요청에는 약 5.5초의 초기화 비용이 포함돼 일반 요청 성능과 분리해야 한다.
- 순차 요청, 706-token 입력, 16-token 출력, 단일 모델 결과이므로 동시성·긴 출력·다른 모델로 일반화할 때 추가 측정이 필요하다.
- LMCache의 장점은 반복 가능한 prefix가 있을 때 발생한다. 매번 완전히 새로운 프롬프트라면 저장 비용만 추가될 수 있다.

## 8. 최종 판단

| 평가 항목 | 판단 |
|---|---|
| LMCache 연결 여부 | ON 로그에서 external hit 지표와 Store/Retrieve 기록으로 확인 |
| 캐시 미사용 기준선 | OFF 로그에 external hit 항목이 없고 두 번째 구간도 약 1.44초 유지 |
| Warm 성능 개선 | 평균 1.441초 → 0.521초 |
| 개선 효과 | 63.9% 지연 감소, 2.77배 속도 |
| 안정성 | ON/OFF 각각 60개 요청 모두 HTTP 200 |
| 적용 가치 | 반복 prefix가 많은 워크로드에서 유의미함 |

따라서 현재 실습 구성에서는 **LMCache 사용이 효과적**이다. 특히 시스템 프롬프트, 긴 문서 문맥, 공통 대화 이력처럼 동일 prefix를 반복하는 서비스에서 이 결과와 유사한 prefill 절감 효과를 기대할 수 있다.

```




Reference
- https://blog.lmcache.ai/en/2026/06/23/vllm-lmcache-a-starter-guide-no-gpu-required
- https://blog.lmcache.ai/en/2026/06/15/understanding-lmcache-mp-mode-transfer-paths-a-beginners-guide/
- https://github.com/orca3/llm-model-inference/blob/main/ch07/LMCache.ipynb
