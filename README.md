# local-ai
Docker compose to load and start ollama and open-webui locally.

# Usage
Start containers using
`scripts/up.sh`

Connect to open-webui afterwards
`http://localhost:3000/`

Stop with
`scripts/down.sh`

Remove containers and volumes (will delete all LLMs, huge download!)
`scripts/remove.sh`

# Configure
Select Models in `scripts/pull-ollama-models.sh` under `DEFAULT_MODELS`.
A list of available LLMs can be found under https://ollama.com/library
