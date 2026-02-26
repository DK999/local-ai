# local-ai
Docker compose to load and start ollama and open-webui locally.

# Usage
## Start containers
`scripts/up.sh`

Connect to open-webui afterwards  
`http://localhost:3000/`

## Stop
`scripts/down.sh`

## Remove 
Containers and volumes (will delete all LLMs, huge download!)  
`scripts/remove.sh`

## Configure LLMs
Write your models in `scripts/pull-ollama-models.sh` under `DEFAULT_MODELS`.  
A list of available LLMs can be found at [https://ollama.com/library][Ollama]
