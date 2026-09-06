# Nginx (proxy con módulo OpenTelemetry)

Proxy nginx (imagen `nginx-otel:latest`, construida aparte) que expone 80/443/3000 y sirve como
entrada compartida para otros stacks (Victoriametrics, WordPress/Rossy).

Los certificados TLS se gestionan con **Let's Encrypt** (certbot, validación HTTP-01 vía
webroot) con renovación automática. Ya no se usan certificados comprados manualmente.

## Uso

### Primera vez (sin certificados aún)

Ejecuta el script de bootstrap, que genera un certificado dummy para poder arrancar nginx,
solicita el certificado real a Let's Encrypt y deja corriendo el servicio de renovación:

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

1. Agrega el `server_name` y las locations correspondientes en
   `compartido/nginx/conf.d/default.conf` (bloque `:80` con
   `/.well-known/acme-challenge/` + redirect, y bloque `:443` apuntando a
   `/etc/letsencrypt/live/<dominio>/fullchain.pem` y `privkey.pem`).
2. Vuelve a correr `DOMAINS="dominio1.zuard.net dominio2.zuard.net" ./init-letsencrypt.sh`
   incluyendo todos los dominios que ya tengan certificado más el nuevo (o ejecuta certbot
   manualmente con `--webroot` para pedir solo el certificado del dominio nuevo).

## Variables

No requiere contraseñas ni secretos en este archivo.

## Requisitos externos (rutas del host)

| Ruta en el host | Uso |
|---|---|
| `/compartido/nginx/conf.d/default.conf` | Config principal de nginx (ver `compartido/nginx/conf.d/`). |
| `/compartido/nginx/includes/proxy.conf` | Includes de proxy (ver `compartido/nginx/includes/`). |
| `/compartido/nginx/certificados/...` | Certificados TLS antiguos / material adicional (privados) — no incluidos en el repo. |
| `/compartido/nginx/letsencrypt/...` | Certificados emitidos por Let's Encrypt (`/etc/letsencrypt`), compartidos entre `nginx-proxy` y `certbot`. Se generan solos, no requieren versionarse. |
| `/compartido/nginx/certbot-webroot/...` | Webroot para el reto ACME HTTP-01 (`/.well-known/acme-challenge/`). Se genera solo. |

El puerto 80 debe estar accesible públicamente para que Let's Encrypt pueda validar el dominio
(reto HTTP-01).

## Redes externas requeridas

- `victoriametrics_vm_net2`
- `wordpress_rossy_default`

Ambas deben existir previamente (`docker network create ...` o creadas por los stacks
Victoriametrics/PaginaRossy).
