# Интеграция информационного киоска

Репка Pi 4 выполняет функции клиента. Backend киоска хранит секреты с правами 0600, не передаёт их браузерному JavaScript.

Для эксплуатации использовать HTTPS с проверкой сертификата. Указать собственный адрес сервера и доверенный CA. Служебному пользователю предоставить только право Read модели и API endpoints /api/models и /api/chat/completions. Раскрытый ключ необходимо отозвать и заменить.

```bash
read -rp 'HTTPS server URL: ' LLM_BASE_URL
read -rsp 'API key: ' LLM_API_KEY; echo
export LLM_BASE_URL LLM_API_KEY
curl -fsS -H "Authorization: Bearer $LLM_API_KEY" "$LLM_BASE_URL/api/models"
```

ID модели брать из ответа, не угадывать. POST /api/chat/completions принимает messages, model, max_tokens, stream. Пример клиента: [llm_client.py](../clients/llm_client.py).

При stream:true обрабатывать SSE, выводить delta.content, а не сырые JSON-события. finish_reason:length означает исчерпание лимита. В лаборатории 256 токенов ушли на reasoning_content; итогового ответа не было. Передача chat_template_kwargs.enable_thinking=false через Open WebUI пока не подтверждена.

Передача фотографии в мультимодальный LLM предполагает image_url с data URI base64; реальный запрос ещё не проверен. Для регистрации фото использовать отдельный VISION API, а не историю чата.
