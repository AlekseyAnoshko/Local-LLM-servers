#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH
IP=${VISION_IP:?Set VISION_IP}
KIOSK=${KIOSK_IP:?Set KIOSK_IP}
DIR=/opt/vision-server
DATA=/srv/vision
[[ $EUID == 0 ]] || { echo 'Run as root'; exit 1; }
valid_ipv4() {
    local a b c d
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r a b c d <<< "$1"
    for octet in "$a" "$b" "$c" "$d"; do
        [[ $octet == 0 || $octet != 0* ]] && ((10#$octet <= 255)) || return 1
    done
}
valid_ipv4 "$IP" && valid_ipv4 "$KIOSK" || { echo 'Invalid IPv4 address'; exit 1; }
[[ ! -e "$DIR/compose.yaml" ]] || { echo 'Existing installation: refusing to overwrite'; exit 1; }
ip -4 -o addr show | grep -F " $IP/" >/dev/null || { echo "Configure $IP first; network unchanged"; exit 1; }
mountpoint -q "$DATA" || { echo "Mount dedicated storage at $DATA before installation"; exit 1; }
apt-get update
apt-get install -y docker-engine docker-compose openssl
systemctl enable --now docker.service
if docker compose version >/dev/null 2>&1; then C=(docker compose); else C=(docker-compose); fi
install -d -m 700 "$DIR" "$DIR/tls" "$DATA/photos" "$DATA/postgres"
cd "$DIR"
openssl rand -hex 32 > api-key
printf 'POSTGRES_PASSWORD=%s\nVISION_IP=%s\nKIOSK_IP=%s\n' "$(openssl rand -hex 32)" "$IP" "$KIOSK" > .env
openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 365 -subj "/CN=$IP" -addext "subjectAltName=IP:$IP" -addext 'extendedKeyUsage=serverAuth' -keyout tls/server.key -out tls/server.crt
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
RUN pip install --no-cache-dir 'fastapi>=0.115,<1' 'uvicorn>=0.34,<1' 'psycopg[binary]>=3.2,<4' 'pillow>=11,<13'
WORKDIR /app
COPY app.py /app/app.py
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8443","--ssl-keyfile","/tls/server.key","--ssl-certfile","/tls/server.crt","--no-access-log","--no-proxy-headers"]
EOF
cat > compose.yaml <<'EOF'
services:
  db:
    image: postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_DB: vision
      POSTGRES_USER: vision
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - /srv/vision/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U vision -d vision"]
      interval: 5s
      timeout: 3s
      retries: 20
  api:
    build: .
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      KIOSK_IP: ${KIOSK_IP}
    ports:
      - "${VISION_IP}:8443:8443"
    volumes:
      - /srv/vision/photos:/photos
      - ./tls:/tls:ro
      - ./api-key:/run/secrets/api-key:ro
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
EOF
cat > app.py <<'PY'
import hashlib, hmac, io, os, re, uuid
from pathlib import Path
from contextlib import asynccontextmanager
import psycopg
from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.responses import JSONResponse
from PIL import Image, ImageOps, ImageStat, UnidentifiedImageError

ROOT = Path('/photos')
KEY = Path('/run/secrets/api-key').read_text().strip()
LIMIT = 5 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 12_000_000

def connect():
    return psycopg.connect(host='db', dbname='vision', user='vision', password=os.environ['POSTGRES_PASSWORD'])

@asynccontextmanager
async def lifespan(app):
    with connect() as conn:
        conn.execute('''CREATE TABLE IF NOT EXISTS photos (
            id uuid PRIMARY KEY, student_id text NOT NULL,
            consent_ref text NOT NULL, filename text NOT NULL UNIQUE,
            sha256 text NOT NULL, width integer NOT NULL, height integer NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now())''')
    yield

app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

def auth(request: Request):
    if not request.client or request.client.host != os.environ['KIOSK_IP']:
        raise HTTPException(403, 'Source address not permitted')
    if not hmac.compare_digest(request.headers.get('authorization','').encode(), ('Bearer '+KEY).encode()):
        raise HTTPException(401, 'Unauthorized')

async def read_image(request):
    raw = bytearray()
    async for chunk in request.stream():
        if len(raw)+len(chunk)>LIMIT:
            raise HTTPException(413, 'Image exceeds 5 MiB')
        raw.extend(chunk)
    try:
        with Image.open(io.BytesIO(raw)) as original:
            if original.format not in ('JPEG','PNG') or original.width*original.height>12_000_000:
                raise HTTPException(400, 'JPEG/PNG up to 12 megapixels required')
            image = ImageOps.exif_transpose(original).convert('RGB')
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(400, 'Invalid image')
    return image

@app.get('/health', dependencies=[Depends(auth)])
def health():
    return {'status':True}

@app.post('/v1/analyze', dependencies=[Depends(auth)])
async def analyze(request: Request):
    image = await read_image(request)
    return {'width':image.width,'height':image.height,'brightness':round(ImageStat.Stat(image.convert('L')).mean[0],1),'stored':False}

@app.post('/v1/photos/{student_id}', dependencies=[Depends(auth)])
async def save(student_id: str, request: Request):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',student_id):
        raise HTTPException(400,'Invalid student ID')
    consent = request.headers.get('X-Consent-Ref','').strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',consent):
        raise HTTPException(400,'Consent reference required')
    image = await read_image(request)
    image.thumbnail((1920,1920))
    buf=io.BytesIO(); image.save(buf,format='JPEG',quality=90)
    data=buf.getvalue(); ident=uuid.uuid4(); filename=f'{ident}.jpg'; path=ROOT/filename
    try:
        with path.open('xb') as f:
            f.write(data)
        path.chmod(0o600)
        with connect() as conn:
            conn.execute('INSERT INTO photos(id,student_id,consent_ref,filename,sha256,width,height) VALUES (%s,%s,%s,%s,%s,%s,%s)',(ident,student_id,consent,filename,hashlib.sha256(data).hexdigest(),image.width,image.height))
    except Exception:
        path.unlink(missing_ok=True)
        raise HTTPException(500,'Storage error')
    return JSONResponse({'id':str(ident),'stored':True},status_code=201)
PY
"${C[@]}" up -d --build
printf '\nVISION: https://%s:8443\nKey: %s/api-key\nCertificate: %s/tls/server.crt\n' "$IP" "$DIR" "$DIR"
