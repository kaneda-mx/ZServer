#!/usr/bin/env bash
# Bootstrap inicial de certificados Let's Encrypt para el proxy nginx compartido.
#
# Resuelve el problema del huevo y la gallina: nginx necesita un certificado en
# /etc/letsencrypt/live/<dominio>/ para arrancar con `listen 443 ssl`, pero ese
# certificado real solo lo emite certbot con nginx ya corriendo (validación
# HTTP-01 vía /.well-known/acme-challenge/). Este script:
#   1. Genera un certificado autofirmado "dummy" para poder arrancar nginx.
#   2. Levanta nginx-proxy.
#   3. Borra el dummy y pide el certificado real a Let's Encrypt (webroot).
#   4. Recarga nginx con el certificado definitivo.
#
# Uso: ./init-letsencrypt.sh
# Variables de entorno opcionales:
#   DOMAINS   Dominios separados por espacio (default: grafana.zuard.net)
#   EMAIL     Email de contacto para Let's Encrypt (default: kanedainc@gmail.com)
#   STAGING   1 para usar el entorno de pruebas de Let's Encrypt (default: 0)

set -euo pipefail

DOMAINS="${DOMAINS:-grafana.zuard.net}"
EMAIL="${EMAIL:-kanedainc@gmail.com}"
STAGING="${STAGING:-0}"

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/ngnix-otel.yml"
LE_DIR="/compartido/nginx/letsencrypt"
WEBROOT_DIR="/compartido/nginx/certbot-webroot"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker no está instalado en este host." >&2
  exit 1
fi

mkdir -p "$LE_DIR" "$WEBROOT_DIR"

domain_args=()
for domain in $DOMAINS; do
  domain_args+=(-d "$domain")
done

staging_arg=""
if [ "$STAGING" != "0" ]; then
  staging_arg="--staging"
fi

first_domain="$(echo "$DOMAINS" | awk '{print $1}')"
dummy_path="$LE_DIR/live/$first_domain"

echo "### Generando certificado dummy para $first_domain ..."
mkdir -p "$dummy_path"
docker run --rm -v "$LE_DIR:/etc/letsencrypt" certbot/certbot:latest \
  sh -c "mkdir -p /etc/letsencrypt/live/$first_domain && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout '/etc/letsencrypt/live/$first_domain/privkey.pem' \
    -out '/etc/letsencrypt/live/$first_domain/fullchain.pem' \
    -subj '/CN=localhost'"

echo "### Levantando nginx-proxy con el certificado dummy ..."
docker compose -f "$COMPOSE_FILE" up -d nginx-proxy

echo "### Borrando el certificado dummy ..."
docker run --rm -v "$LE_DIR:/etc/letsencrypt" certbot/certbot:latest \
  sh -c "rm -rf /etc/letsencrypt/live/$first_domain /etc/letsencrypt/archive/$first_domain /etc/letsencrypt/renewal/$first_domain.conf"

echo "### Solicitando el certificado real a Let's Encrypt ..."
docker run --rm \
  -v "$LE_DIR:/etc/letsencrypt" \
  -v "$WEBROOT_DIR:/var/www/certbot" \
  certbot/certbot:latest certonly \
  --webroot -w /var/www/certbot \
  $staging_arg \
  --email "$EMAIL" --agree-tos --no-eff-email \
  "${domain_args[@]}" --force-renewal

echo "### Recargando nginx-proxy con el certificado definitivo ..."
docker exec nginx-otel nginx -s reload

echo "### Levantando el servicio certbot de renovación automática ..."
docker compose -f "$COMPOSE_FILE" up -d certbot

echo "Listo. Certificados en $LE_DIR/live/$first_domain/"
