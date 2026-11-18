#!/bin/sh
# Prepara pastas, .env e configs iniciais. Nao sobrescreve nada que ja exista. Rode antes do primeiro "up".
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|/home/USUARIO|$HOME|g" .env
  sed -i "s|^PUID=.*|PUID=$(id -u)|; s|^PGID=.*|PGID=$(id -g)|" .env
  RG=$(getent group render | cut -d: -f3 || true)
  [ -n "$RG" ] && sed -i "s|^RENDER_GID=.*|RENDER_GID=$RG|" .env
  IP=$(hostname -I | awk '{print $1}')
  [ -n "$IP" ] && sed -i "s|^HOST=.*|HOST=$IP|; s|^HOMEPAGE_ALLOWED_HOSTS=.*|HOMEPAGE_ALLOWED_HOSTS=$IP:8082|" .env
  echo ">> .env criado. Revise (principalmente PUID/PGID se usar Podman rootless: 0 e 0)."
fi

. ./.env
mkdir -p "$DATA"/jellyfin/config "$DATA"/jellyfin/cache \
         "$DATA"/qbittorrent/qBittorrent "$DATA"/prowlarr "$DATA"/radarr "$DATA"/sonarr "$DATA"/bazarr "$DATA"/homepage \
         "$MEDIA"/filmes "$MEDIA"/series "$MEDIA"/downloads

copy_if_missing() { [ -e "$2" ] || { cp "$1" "$2" && echo ">> copiado $2"; }; }
copy_if_missing templates/qbittorrent/qBittorrent.conf "$DATA/qbittorrent/qBittorrent/qBittorrent.conf"
copy_if_missing templates/homepage/services.yaml "$DATA/homepage/services.yaml"
copy_if_missing templates/homepage/settings.yaml "$DATA/homepage/settings.yaml"

echo ">> Pronto. Proximo passo: docker compose up -d   (ou: podman compose up -d)"
echo ">> Depois siga o README.md, secao 'Configurar os apps'."
