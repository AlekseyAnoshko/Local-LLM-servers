# VISION — сервер фотографий

Прототип для ALT Server, Docker, PostgreSQL 17, FastAPI и Pillow. Установщик не настраивает сеть, не форматирует диски и не устанавливает GPU-драйверы. Нейросетевой анализ и идентификация личности не реализованы. Не использовать реальные фотографии студентов.

## Установка

Подготовить статический IPv4, доступ к репозиториям и Docker Hub, отдельную файловую систему, смонтированную в /srv/vision. Скрипт проверяет наличие точки монтирования, но не создаёт её. Указать фактические адреса интерактивно:

```bash
read -rp 'VISION IPv4: ' VISION_IP
read -rp 'Kiosk IPv4: ' KIOSK_IP
sudo env VISION_IP="$VISION_IP" KIOSK_IP="$KIOSK_IP" bash deploy/vision/install-vision.sh
```

Повторный запуск при существующем compose.yaml блокируется. Автоматического отката после частичной ошибки нет.

## API

Все endpoints требуют Bearer API key и допустимый IP. HTTPS с самоподписанным сертификатом; передать сертификат и ключ на киоск доверенным каналом. Ключ хранить с правами 0600. Не отключать проверку сертификата.

| Метод | Результат |
|---|---|
| GET /health | status:true |
| POST /v1/analyze | размеры, яркость, stored:false |
| POST /v1/photos/{student_id} | UUID сохранённого JPEG, stored:true |

Тело POST — сырой JPEG/PNG, не multipart. До 5 МиБ и 12 мегапикселей. Для сохранения требуется X-Consent-Ref; идентификаторы ASCII, буквы, цифры, дефис, подчёркивание. Ссылка на согласие сама по себе не доказывает его наличие. Фото уменьшается до 1920×1920 и сохраняется без исходного EXIF. PostgreSQL хранит метаданные и SHA-256 сохранённого файла.

Пример анализа синтетического изображения с киоска:

```bash
read -rp 'VISION HTTPS URL: ' VISION_URL
read -rsp 'VISION API key: ' VISION_KEY; echo
curl --fail-with-body --cacert server.crt \
  -H "Authorization: Bearer $VISION_KEY" \
  -H 'Content-Type: image/jpeg' \
  --data-binary @synthetic.jpg "$VISION_URL/v1/analyze"
unset VISION_KEY
```

Конфигурация /opt/vision-server, данные /srv/vision. Перед эксплуатацией нужны firewall, проверка source IP при Docker NAT, непривилегированный контейнер, аудит, удаление, резервное копирование и проверка согласия. Прототип API работает от root с cap_drop ALL, что не является полноценной изоляцией. Установщик не проверен на реальном сервере.
