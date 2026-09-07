#!/usr/bin/env bash
# Bootstrap inicial de certificados Let's Encrypt (DNS-01 vía Cloudflare) para el proxy
# nginx compartido. Al validar por DNS (registro TXT), no depende de que el puerto 80
# esté accesible desde internet: certbot puede pedir el certificado real antes de levantar
# nginx, sin necesidad de un certificado dummy.
#
# Requisito previo: un archivo de credenciales de Cloudflare con permisos 600, contenido:
#   dns_cloudflare_api_token = TU_TOKEN
# (token con permiso "Zone:DNS:Edit" restringido a la(s) zona(s) de los dominios pedidos)
#
# Si los dominios de una corrida pertenecen a una zona/token distinto del default
# (p.ej. zuard.net vs draquimbert.com.mx), pasa CF_INI (ruta en el host) y CF_INI_NAME
# (nombre con el que se monta dentro del contenedor, debe ser distinto por token para que
# el servicio de renovación pueda tener montados varios tokens a la vez sin pisarse).
#
# Uso: ./init-letsencrypt.sh
# Variables de entorno opcionales:
#   DOMAINS      Dominios separados por espacio (default: grafana.zuard.net)
#   EMAIL        Email de contacto para Let's Encrypt (default: kanedainc@gmail.com)
#   STAGING      1 para usar el entorno de pruebas de Let's Encrypt (default: 0)
#   CF_INI       Ruta en el host al archivo de credenciales de Cloudflare
#                (default: /compartido/nginx/cloudflare.ini)
#   CF_INI_NAME  Nombre del archivo dentro del contenedor (default: cloudflare.ini)

set -euo pipefail

DOMAINS="${DOMAINS:-grafana.zuard.net}"
EMAIL="${EMAIL:-kanedainc@gmail.com}"
STAGING="${STAGING:-0}"
CF_INI="${CF_INI:-/compartido/nginx/cloudflare.ini}"
CF_INI_NAME="${CF_INI_NAME:-cloudflare.ini}"

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/ngnix-otel.yml"
LE_DIR="/compartido/nginx/letsencrypt"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker no está instalado en este host." >&2
  exit 1
fi

if [ ! -f "$CF_INI" ]; then
  echo "Error: no existe $CF_INI. Créalo con 'dns_cloudflare_api_token = TU_TOKEN' y chmod 600." >&2
  exit 1
fi

mkdir -p "$LE_DIR"

domain_args=()
for domain in $DOMAINS; do
  domain_args+=(-d "$domain")
done

staging_arg=""
if [ "$STAGING" != "0" ]; then
  staging_arg="--staging"
fi

for domain in $DOMAINS; do
  live_dir="$LE_DIR/live/$domain"
  renewal_conf="$LE_DIR/renewal/$domain.conf"
  if [ -d "$live_dir" ] && [ ! -f "$renewal_conf" ]; then
    echo "### Limpiando directorio residual sin lineage válido de certbot: $live_dir ..."
    rm -rf "$live_dir" "$LE_DIR/archive/$domain"
  fi
done

echo "### Solicitando certificado a Let's Encrypt vía DNS-01 (Cloudflare) ..."
docker run --rm \
  -v "$LE_DIR:/etc/letsencrypt" \
  -v "$CF_INI:/etc/letsencrypt/$CF_INI_NAME:ro" \
  certbot/dns-cloudflare:latest certonly \
  --dns-cloudflare --dns-cloudflare-credentials "/etc/letsencrypt/$CF_INI_NAME" \
  --dns-cloudflare-propagation-seconds 30 \
  $staging_arg \
  --email "$EMAIL" --agree-tos --no-eff-email \
  "${domain_args[@]}"

echo "### Levantando nginx-proxy con el certificado real ..."
docker compose -f "$COMPOSE_FILE" up -d nginx-proxy
docker exec nginx-otel nginx -s reload 2>/dev/null || true

echo "### Levantando el servicio certbot de renovación automática ..."
docker compose -f "$COMPOSE_FILE" up -d certbot

echo "Listo. Certificados en $LE_DIR/live/<dominio>/"
