# LLM-2: руководство по воспроизведению

Зафиксированная рабочая конфигурация ALT Server 11.1 x86_64, RTX 4060, драйвер 595.104.02, CUDA toolkit 12.9.1. Это не универсальный автоматический установщик. Сначала подготовить сеть, драйвер и отдельный диск без форматирования существующих данных.

## llama.cpp

Собрать из проверенной версии исходников, записав commit SHA. Рабочие параметры CMake:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DGGML_CCACHE=OFF -DLLAMA_BUILD_TESTS=OFF
cmake --build build --config Release -j 10
```

На ALT для линковки потребовались nvidia-cuda-devel-static и libgomp13-devel. Веса модели скачиваются отдельно из доверенного источника с проверкой лицензии и контрольной суммы. Используется Qwen3.8-27B-Q4_K_M.gguf и соответствующий mmproj-Qwen3.8-27B-Q8_0.gguf. Источник весов и commit сборки в имеющихся материалах не зафиксированы.

Пример systemd — [qwen.service.example](../deploy/llm-alt/qwen.service.example). Адаптировать пути и пользователя, затем установить unit в /etc/systemd/system, выполнить daemon-reload и enable --now. Не перезапускать во время активной генерации.

## Open WebUI

Подтверждённая версия 0.13.5. Использовать проверенный образ, постоянный каталог /srv/ai/open-webui, host networking, PORT=3000, ENABLE_OLLAMA_API=false, OPENAI_API_BASE_URL=http://127.0.0.1:8082/v1. Сохранять WEBUI_SECRET_KEY вне Git. Прямой backend не публиковать в сети. Включить TLS на внешнем reverse proxy и ограничить доступ firewall.

При проблеме TLS ClientHello с PQ-группами в контейнере помог отдельный OpenSSL config с Groups = X25519:P-256:P-384; применять только при воспроизведённой проблеме, не отключать проверку сертификатов.

После первого администратора закрыть регистрацию. Отключить автоматические заголовки, теги, follow-up и поисковые запросы в настройках задач. Создать отдельного пользователя киоска, группу с features.api_keys, предоставить Read к модели через Admin Settings → Models. Ограничить API-ключи нужными endpoints.

## Локальный GUI

Xorg, xinit, Openbox, Chromium, fonts-ttf-dejavu, fonts-ttf-liberation, fontconfig. Отсутствие TTF вызвало падение Skia (exit 133). После установки шрифтов выполнить fc-cache -f. Для X11: setxkbmap -layout us,ru -option grp:alt_shift_toggle. Chromium запускать от отдельного непривилегированного пользователя, --disable-gpu для экономии VRAM. Не отключать sandbox.

## Диагностика

```bash
nvidia-smi
journalctl -u qwen.service -n 30 --no-pager
curl -fsS http://127.0.0.1:8082/v1/models
docker ps
```
