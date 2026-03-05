# local-ai
Docker compose to load and start ollama and open-webui locally.

# Usage
## Start containers
`scripts/up.sh`

Connect to open-webui afterwards  
`http://localhost:3000/`  

```
❯ scripts/up.sh             
▶ Detected profile: nvidia
Detected VRAM (host): 16376
▶ Starting Ollama service: ollama-nvidia (Profile: nvidia)
[+] up 1/1
 ✔ Container ollama-nvidia Running                                                                                                                                                                               0.0s
✅ Service 'ollama-nvidia' is HEALTHY (Container: ollama-nvidia)
📦 Starting pull init (one-shot): ollama-init-nvidia
Detected VRAM: 16376
[+]  1/1t 1/11
 ✔ Container ollama-nvidia Running                                                                                                                                                                               0.0s
Container ollama-nvidia Waiting 
Container ollama-nvidia Healthy 
Container ollama-stack-ollama-init-nvidia-run-263179f51d1b Creating 
Container ollama-stack-ollama-init-nvidia-run-263179f51d1b Created 
[2026-03-05 05:09:10] ▶ Ollama Model Puller – Start
[2026-03-05 05:09:10] ⏳ Waiting for Ollama API at http://ollama-nvidia:11434 ...
[2026-03-05 05:09:10] ✅ Ollama API reachable (via ollama CLI).
[2026-03-05 05:09:10] 🧠 Detected VRAM: 16376 MB
[2026-03-05 05:09:10] 📦 Target list:
  - deepseek-r1:14b-q8_0
  - qwen3-embedding:0.6b
  - dengcao/qwen3-reranker-0.6b:q8_0
  - qwen2.5-coder:1.5b-base
[2026-03-05 05:09:10] → Pull: deepseek-r1:14b-q8_0
pulling manifest 
Error: pull model manifest: file does not exist
[2026-03-05 05:09:11]    ... Fallback without quant: deepseek-r1:14b
pulling manifest 
pulling 6e9f90f02bb3: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 9.0 GB                         
pulling c5ad996bda6e: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  556 B                         
pulling 6e4c38e1172f: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 1.1 KB                         
pulling f4d24e9138dd: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  148 B                         
pulling 3c24b0c80794: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  488 B                         
verifying sha256 digest 
writing manifest 
success 
[2026-03-05 05:09:12] → Pull: qwen3-embedding:0.6b
pulling manifest 
pulling 06507c7b4268: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 639 MB                         
pulling 9202febed9e2: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  266 B                         
verifying sha256 digest 
writing manifest 
success 
[2026-03-05 05:09:12] → Pull: dengcao/qwen3-reranker-0.6b:q8_0
pulling manifest 
pulling ad693e485b0b: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 639 MB                         
pulling eb4402837c78: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 1.5 KB                         
pulling cff3f395ef37: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  120 B                         
pulling f331baf917ff: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  414 B                         
verifying sha256 digest 
writing manifest 
success 
[2026-03-05 05:09:13] → Pull: qwen2.5-coder:1.5b-base
pulling manifest 
pulling 6a7736639577: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏ 986 MB                         
pulling 96f5a2272876: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  117 B                         
pulling 832dd9e00a68: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  11 KB                         
pulling b4180e3ea7c6: 100% ▕███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▏  413 B                         
verifying sha256 digest 
writing manifest 
success 
[2026-03-05 05:09:13] 🏁 Done. Installed models:
NAME                                 ID              SIZE      MODIFIED               
qwen2.5-coder:1.5b-base              02e0f2817a89    986 MB    Less than a second ago    
dengcao/qwen3-reranker-0.6b:q8_0     c9da58824943    639 MB    Less than a second ago    
qwen3-embedding:0.6b                 ac6da0dfba84    639 MB    1 second ago              
deepseek-r1:14b                      c333b7232bdb    9.0 GB    1 second ago              
✅ Models loaded (if not already present).
💻 Starting Open‑WebUI: open-webui-nvidia
[+] up 2/2
 ✔ Container ollama-nvidia                    Healthy                                                                                                                                                            0.5s
 ✔ Container ollama-stack-open-webui-nvidia-1 Started                                                                                                                                                            0.2s
🔗 Open‑WebUI: http://localhost:3000
🎉 Success: profile 'nvidia' is running.
```

## Stop
`scripts/down.sh`

## Remove 
Containers and volumes (will delete all LLMs, huge download!)  
`scripts/remove.sh`

## Configure LLMs
Write your models in `scripts/pull-ollama-models.sh` under `DEFAULT_MODELS`.  
A list of available LLMs can be found at [Ollama](https://ollama.com/library)
