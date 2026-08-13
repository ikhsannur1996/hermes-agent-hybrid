# Hermes Agent Hybrid — API Usage Tutorial

The Hermes gateway exposes a fully **OpenAI-compatible** API. Any OpenAI SDK or HTTP client can talk to it — just change the `base_url`.

## Base URL

```
http://YOUR_SERVER_IP:8642/v1
```

## Authentication

Every request must include an `Authorization` header:

```
Authorization: Bearer YOUR_API_KEY
```

> The API key is generated at install time. Find it in `~/hermes-connection.txt` or `~/.hermes/.env`.

---

## 1. Health Check

```bash
curl http://YOUR_SERVER_IP:8642/health \
  -H "Authorization: Bearer YOUR_API_KEY"
```

**Example response:**
```json
{
  "status": "ok",
  "version": "0.x.x"
}
```

---

## 2. List Models

```bash
curl http://YOUR_SERVER_IP:8642/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

**Example response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "hermes-agent",
      "object": "model",
      "created": 1234567890,
      "owned_by": "hermes"
    }
  ]
}
```

> The virtual model `hermes-agent` is the only model exposed. It routes to your local model (with fallback).

---

## 3. Chat Completions — Basic

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }'
```

**Example response:**
```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "hermes-agent",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 14,
    "completion_tokens": 8,
    "total_tokens": 22
  }
}
```

---

## 4. Multi-turn Conversation

Include the conversation history to maintain context:

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [
      {"role": "user", "content": "My name is Alice."},
      {"role": "assistant", "content": "Hello Alice! How can I help you today?"},
      {"role": "user", "content": "What is my name?"}
    ]
  }'
```

---

## 5. System Prompt

Set a system prompt to steer the model's behavior:

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant. Always include code examples."},
      {"role": "user", "content": "Write a Python function to reverse a string."}
    ]
  }'
```

---

## 6. Streaming Responses

Add `"stream": true` to get token-by-token Server-Sent Events (SSE):

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [{"role": "user", "content": "Count from 1 to 5."}],
    "stream": true
  }'
```

---

## 7. Using OpenAI SDK (Python)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://YOUR_SERVER_IP:8642/v1",
    api_key="YOUR_API_KEY",
)

response = client.chat.completions.create(
    model="hermes-agent",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain quantum computing in one sentence."},
    ]
)

print(response.choices[0].message.content)
```

### Streaming with the SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://YOUR_SERVER_IP:8642/v1",
    api_key="YOUR_API_KEY",
)

stream = client.chat.completions.create(
    model="hermes-agent",
    messages=[{"role": "user", "content": "Write a poem about AI."}],
    stream=True,
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

---

## 8. Using OpenAI SDK (Node.js / TypeScript)

```javascript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "http://YOUR_SERVER_IP:8642/v1",
  apiKey: "YOUR_API_KEY",
});

const response = await client.chat.completions.create({
  model: "hermes-agent",
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "What is the meaning of life?" },
  ],
});

console.log(response.choices[0].message.content);
```

---

## 9. Error Codes

| HTTP Status | Meaning |
|-------------|---------|
| `200` | Success |
| `400` | Bad request (invalid JSON, missing fields) |
| `401` | Missing or invalid API key |
| `404` | Endpoint not found |
| `429` | Rate limited |
| `500` | Upstream error (Ollama or OpenRouter) |
| `503` | Service unavailable (model not loaded) |

---

## 10. Quick Reference

```
┌──────────────────────────────────────────────────────────────┐
│  POST /v1/chat/completions                                   │
│  GET  /v1/models                                             │
│  GET  /health                                                │
│                                                              │
│  Headers:  Authorization: Bearer <key>                       │
│            Content-Type: application/json                     │
│                                                              │
│  Body:     {"model":"hermes-agent","messages":[...]}          │
│                                                              │
│  Stream:   {"model":"hermes-agent","messages":[...],"stream":true}
└──────────────────────────────────────────────────────────────┘
```

## Next Tutorial

→ [05-advanced.md](05-advanced.md)
