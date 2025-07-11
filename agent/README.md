USAGE TL;DR

# 1. If user not previously, Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh 

# 2. Start service
ollama serve

# 3. Download model (one time)
ollama pull llama3.2:latest

# 4. Test
ollama run llama3.2:latest


# Install new dependencies
npm install ethers dotenv @langchain/ollama @langchain/core @langchain/langgraph

# Start Ollama (keep running)
ollama serve

# Run human player
npm run start

# Run AI agent (separate terminal)
npm run agent



README:

# 🦙 Ollama Setup Guide for DicePoker Agent

The poker agent now uses **Ollama** - a free, local LLM solution instead of OpenAI API. No API keys needed!

## 🚀 Quick Setup

### 1. Install Ollama

**macOS/Linux:**
```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

**Windows:**
Download from: https://ollama.ai/download

### 2. Start Ollama Service
```bash
ollama serve
```
*Keep this running in a separate terminal*

### 3. Pull the Model
```bash
# Download Llama 3.2 (3.2GB - fast and smart)
ollama pull llama3.2:latest

# Alternative models:
# ollama pull phi3:mini          # Smaller (2.2GB)
# ollama pull mistral:latest     # Different personality (4.1GB)
# ollama pull codellama:latest   # Code-focused (3.8GB)
```

### 4. Test Ollama
```bash
# Quick test
ollama run llama3.2:latest
# Type: "Hello, how are you?"
# Press Ctrl+D to exit
```

## 🎮 Run the Poker Agent

```bash
# Install dependencies (updated for Ollama)
npm install ethers dotenv @langchain/ollama @langchain/core @langchain/langgraph

# Run the agent
npm run agent
```

## ⚙️ Configuration Options

### Model Selection
Change the model in `.env`:
```bash
# Fast and efficient (recommended)
OLLAMA_MODEL=llama3.2:latest

# Smaller, faster model
OLLAMA_MODEL=phi3:mini

# Creative responses
OLLAMA_MODEL=mistral:latest
```

### Custom Ollama Setup
```bash
# If Ollama runs on different port/host
OLLAMA_BASE_URL=http://localhost:11434

# For remote Ollama instance
OLLAMA_BASE_URL=http://your-server:11434
```

## 🔧 Troubleshooting

### Ollama Not Found
```bash
# Check if Ollama is running
curl http://localhost:11434/api/version

# Should return: {"version":"0.x.x"}
```

### Model Not Available
```bash
# List installed models
ollama list

# If empty, pull a model:
ollama pull llama3.2:latest
```

### Port Issues
```bash
# Check what's using port 11434
lsof -i :11434

# Kill existing process if needed
pkill ollama

# Restart
ollama serve
```

### Memory Issues
```bash
# For systems with <8GB RAM, use smaller model:
ollama pull phi3:mini
```

## 🎭 Agent Behavior

The agent now:
- ✅ **Runs completely offline** - no API calls
- ✅ **Fast responses** - local inference  
- ✅ **Free forever** - no usage costs
- ✅ **Privacy-first** - data stays local
- ✅ **Fallback logic** - works even if LLM fails

### Sample Agent Messages:
```
🤖 Agent: "Time to separate the wheat from the chaff."
💰 Agent placing bet of 0.5 FLOW...

🤖 Agent: "The dice favor the bold today."
🎲 Agent rolling dice with VRF...

🤖 Agent: "Discretion is the better part of valor."
🏳️ Agent folding...
```

## 📊 Model Comparison

| Model | Size | Speed | Personality | Recommended For |
|-------|------|-------|-------------|-----------------|
| `llama3.2:latest` | 3.2GB | Fast | Balanced | **Best overall** |
| `phi3:mini` | 2.2GB | Fastest | Concise | Low-end systems |
| `mistral:latest` | 4.1GB | Medium | Creative | Rich conversations |
| `codellama:latest` | 3.8GB | Medium | Technical | Strategy-focused |

## 🚀 Performance Tips

1. **Keep Ollama running** - Startup takes ~10 seconds
2. **Use SSD storage** - Models load faster
3. **8GB+ RAM recommended** - For smooth inference
4. **GPU acceleration** - Ollama auto-detects CUDA/Metal

## 🔄 Updating

```bash
# Update Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Update models
ollama pull llama3.2:latest
```

Now your poker agent runs completely free with local AI! 🎲🤖