## LLM Serving 스터디 5주차 

### 크롬 환경 설정
`chrome://chrome-urls/?host=chrome://tracing/#internal-debug-pages` 접속하여 `chrome://tracing` 이 속해있는 항목이 활성화되어있는지 확인한다. 기본 값은 비활성화이기 떄문에 이를 활성화후 `chrome://tracing/` 에 들어간다.

<img width="304" height="614" alt="image" src="https://github.com/user-attachments/assets/9f314a85-ada9-4369-b752-3a059259cc66" />

접속 후에는 colab 또는 pytorch 프로파일러에서 수행했던 결과물(trace.json)에 대해서 Load 버튼을 클릭하여 정보를 읽어들인다.

<img width="881" height="801" alt="image" src="https://github.com/user-attachments/assets/829b08c3-b291-4bfa-bc9c-e0fb1194cd02" />

Reference
- https://huggingface.co/blog/torch-profiler 
- https://tutorials.pytorch.kr/recipes/recipes/profiler_recipe.html
- https://docs.nvidia.com/nsight-systems/InstallationGuide/index.html
- https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html
