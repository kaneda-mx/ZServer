# Nginx (proxy con módulo OpenTelemetry)

Proxy nginx (imagen `nginx-otel:latest`, construida aparte) que expone 80/443/3000 y sirve como
entrada compartida para otros stacks (Victoriametrics, WordPress/Rossy).

Los certificados TLS se gestionan con **Let's Encrypt** (certbot, validación **DNS-01** vía
la API de Cloudflare) con renovación automática. Ya no se usan certificados comprados
manualmente. Se usa DNS-01 en vez de HTTP-01 porque el puerto 80 del host no es alcanzable
desde internet (firewall del propio Linux, con casi todos los puertos cerrados salvo los
necesarios); DNS-01 no depende de ningún puerto entrante.

## Uso

### Requisito previo: token de Cloudflare

El dominio `zuard.net` está gestionado en Cloudflare. Crea un archivo
`/compartido/nginx/cloudflare.ini` (fuera del repo, solo en el host) con:

```ini
dns_cloudflare_api_token = TU_TOKEN
```

El token debe crearse en Cloudflare → My Profile → API Tokens → plantilla **"Edit zone DNS"**,
restringido a la zona `zuard.net` únicamente. Luego:

```bash
chmod 600 /compartido/nginx/cloudflare.ini
```

### Primera vez (sin certificados aún)

Ejecuta el script de bootstrap, que pide el certificado real a Let's Encrypt (sin necesidad de
tener nginx corriendo antes, al validar por DNS) y deja corriendo el servicio de renovación:

```bash
./init-letsencrypt.sh
```

Variables opcionales: `DOMAINS` (default `grafana.zuard.net`), `EMAIL` (default
`kanedainc@gmail.com`), `STAGING=1` para probar contra el entorno de pruebas de Let's Encrypt
antes de pedir el certificado real (evita el rate limit de Let's Encrypt mientras pruebas).

### Arranque normal (certificados ya emitidos)

```bash
docker compose -f ngnix-otel.yml up -d
```

Esto levanta `nginx-proxy` y el servicio `certbot`, que corre en segundo plano y ejecuta
`certbot renew` cada 12 horas (certbot solo renueva si el certificado está a menos de 30 días
de expirar).

### Añadir un nuevo dominio con Let's Encrypt

1. Agrega el `server_name` y el bloque `:443` en `compartido/nginx/conf.d/default.conf`,
   apuntando a `/etc/letsencrypt/live/<dominio>/fullchain.pem` y `privkey.pem`. Si el dominio
   también está en la zona `zuard.net` (o cualquier otra ya cubierta por el mismo token de
   Cloudflare) no necesitas tocar nada más de DNS.
2. Vuelve a correr `DOMAINS="dominio1.zuard.net dominio2.zuard.net" ./init-letsencrypt.sh`
   incluyendo todos los dominios que ya tengan certificado más el nuevo.

## Variables

No requiere contraseñas ni secretos en este archivo.

## Requisitos externos (rutas del host)

| Ruta en el host | Uso |
|---|---|
| `/compartido/nginx/conf.d/default.conf` | Config principal de nginx (ver `compartido/nginx/conf.d/`). |
| `/compartido/nginx/includes/proxy.conf` | Includes de proxy (ver `compartido/nginx/includes/`). |
| `/compartido/nginx/certificados/...` | Certificados TLS antiguos / material adicional (privados) — no incluidos en el repo. |
| `/compartido/nginx/letsencrypt/...` | Certificados emitidos por Let's Encrypt (`/etc/letsencrypt`), compartidos entre `nginx-proxy` y `certbot`. Se generan solos, no requieren versionarse. |
| `/compartido/nginx/cloudflare.ini` | Credencial de la API de Cloudflare para la validación DNS-01. **No versionar, modo 600.** |
| `/compartido/nginx/certbot-webroot/...` | Sin uso mientras se valide por DNS-01. Se deja montado por si algún dominio futuro no está en Cloudflare y necesita HTTP-01. |

## Redes externas requeridas

- `victoriametrics_vm_net2`
- `wordpress_rossy_default`

Ambas deben existir previamente (`docker network create ...` o creadas por los stacks
Victoriametrics/PaginaRossy).
