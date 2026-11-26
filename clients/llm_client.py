"""Minimal HTTPS client for the kiosk; no third-party dependencies."""
import json
import os
import ssl
import urllib.request
from urllib.parse import urlsplit

base = os.environ["LLM_BASE_URL"].rstrip("/")
if urlsplit(base).scheme != "https":
    raise SystemExit("HTTPS required")
token = os.environ["LLM_API_KEY"]
context = ssl.create_default_context(cafile=os.getenv("LLM_CA_FILE"))

def request(path, data=None):
    req = urllib.request.Request(
        base + path,
        data=None if data is None else json.dumps(data).encode("utf-8"),
        headers={"Authorization": "Bearer " + token,
                 "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, context=context, timeout=300) as response:
        return json.load(response)

if __name__ == "__main__":
    models = request("/api/models")["data"]
    if not models:
        raise SystemExit("No accessible models")
    for model in models:
        print(model["id"])
    selected = input("Model ID: ").strip()
    if selected not in {m["id"] for m in models}:
        raise SystemExit("Unknown model")
    result = request("/api/chat/completions", {
        "model": selected,
        "messages": [{"role": "user", "content": input("Question: ")}],
        "max_tokens": 512,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    })
    choice = result["choices"][0]
    print(choice["message"].get("content") or "No final answer")
    print("Finish:", choice.get("finish_reason"))
