# Servidor de streaming doméstico

Stack de containers: **Jellyfin** (biblioteca), **Radarr/Sonarr** (filmes/séries), **Prowlarr** (indexadores), **FlareSolverr** (apoio ao Prowlarr), **Bazarr** (legendas), **qBittorrent** (downloads) e **Homepage** (painel).
Pensado para um notebook/mini-PC modesto (testado em Celeron N4020, 4 GB de RAM, Debian 13) acessado só por SSH. Use apenas com conteúdo que você tem direito de baixar e assistir.

Este guia serve para uma pessoa ou um agente que parte de uma máquina vazia. As seções 1 a 3 preparam o sistema, a 4 sobe o stack, a 5 configura os apps (parte manual, porque os apps guardam chaves de API geradas na hora) e a 6 trata de extras e problemas.

## O que o repositório contém

| Caminho | Para quê |
|---|---|
| `compose.yaml` | os serviços |
| `.env.example` | variáveis (o `setup.sh` cria o `.env`) |
| `setup.sh` | cria pastas, `.env` e copia configs iniciais |
| `templates/homepage/` | `services.yaml` e `settings.yaml` do painel |
| `templates/qbittorrent/qBittorrent.conf` | libera o acesso à interface web na LAN |
| `templates/custom-formats/ptbr-dublado.json` | Custom Format do Radarr/Sonarr para preferir dublado |
| `docs/restic.md` | tutorial de backup (opcional) |

**Não está no repositório (de propósito):** chaves de API, senhas, definições de indexadores e as configurações internas dos apps. Elas são geradas ou escolhidas por você na seção 5.

## 1. Pré-requisitos do sistema (fora do stack)

1. **Debian 13** instalado só com "utilitários padrão do sistema" e "servidor SSH".
2. **Usuário com sudo:** `su -`, `apt install sudo`, `usermod -aG sudo SEU_USUARIO`.
3. **IP fixo:** reserve o IP do servidor no roteador (DHCP por MAC). Anote-o: é o `HOST` do `.env`.
4. **SSH por chave** (recomendado): `ssh-copy-id usuario@IP` do seu PC. Depois, opcionalmente, `PasswordAuthentication no` em `/etc/ssh/sshd_config`.
5. **Notebook com a tampa fechada:** em `/etc/systemd/logind.conf` defina `HandleLidSwitch=ignore`, `HandleLidSwitchExternalPower=ignore`, `HandleLidSwitchDocked=ignore` e rode `sudo systemctl restart systemd-logind`.
6. **Wi-Fi** (se não houver cabo): `sudo apt install network-manager`, depois `nmcli device wifi connect "SSID" password "SENHA"`. Prefira cabo; se usar Wi-Fi, 5 GHz.
7. **Ferramentas:** `sudo apt install -y curl htop`.

## 2. Container engine (escolha um)

### Opção A: Podman rootless (usada no projeto original)
```
sudo apt install -y podman podman-compose
sudo loginctl enable-linger $USER        # containers sobem sozinhos sem sessão aberta
```
No `.env`, use `PUID=0` e `PGID=0` (dentro do container, root mapeia para o seu usuário, e os arquivos ficam seus).
`docker compose` pode ser substituído por `podman compose`. Para reiniciar sozinho no boot, use também `podman generate systemd` ou converta para Quadlet (arquivos em `~/.config/containers/systemd/`); o `restart: unless-stopped` do compose só funciona se o serviço `podman-restart` estiver ativo: `systemctl --user enable --now podman-restart.service`.

### Opção B: Docker
```
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER            # saia e entre de novo na sessão
```
No `.env`, use `PUID` e `PGID` do seu usuário (`id -u`, `id -g`; o `setup.sh` já preenche).

## 3. Firewall (recomendado)

Libere só a rede local (troque `192.168.1.0/24` pela sua):
```
sudo apt install -y ufw
sudo ufw default deny incoming
for p in 22 8096 8081 8082 9696 7878 8989 6767; do
  sudo ufw allow from 192.168.1.0/24 to any port $p proto tcp
done
sudo ufw allow 6881/tcp && sudo ufw allow 6881/udp   # porta de torrent (opcional)
sudo ufw enable
```
Atenção: o Docker publica portas direto no iptables e ignora o ufw. Com Docker, não abra o roteador para essas portas.

## 4. Subir o stack

```
git clone https://github.com/antonylrds/sistema_streaming.git
cd sistema_streaming
sh setup.sh            # cria .env, pastas e configs iniciais
nano .env              # confira HOST, PUID/PGID, caminhos
docker compose config  # valida o arquivo (ou: podman compose config)
docker compose up -d   # (ou: podman compose up -d)
docker compose ps      # todos devem estar "running"
```
Memória: 8 serviços em ~3,4 GB de RAM sobram cerca de 1 GB. Se faltar, pare o que não usa (`docker compose stop bazarr`).

Endereços (troque `IP`):

| Serviço | URL |
|---|---|
| Homepage | `http://IP:8082` |
| Jellyfin | `http://IP:8096` |
| qBittorrent | `http://IP:8081` |
| Radarr / Sonarr | `http://IP:7878` / `http://IP:8989` |
| Prowlarr | `http://IP:9696` |
| Bazarr | `http://IP:6767` |

Dentro dos apps, use os **nomes dos serviços** (não o IP): `qbittorrent:8080`, `radarr:7878`, `sonarr:8989`, `prowlarr:9696`, `flaresolverr:8191`. Estão na mesma rede do compose.

## 5. Configurar os apps (nesta ordem)

Convenção de pastas dentro dos containers: tudo em `/media` (a mesma pasta `${MEDIA}` do host em todos). Isso permite **hardlinks** (o download e a biblioteca ocupam o espaço uma vez só).
- `/media/filmes`: biblioteca de filmes
- `/media/series`: biblioteca de séries
- `/media/downloads`: downloads do qBittorrent

### 5.1 qBittorrent (`http://IP:8081`)
1. Usuário `admin`. A senha temporária aparece no log: `docker compose logs qbittorrent | grep -i password`. Ela muda a cada reinício até você definir uma.
2. **Ferramentas → Opções → Interface Web:** defina um usuário e senha definitivos.
3. **Opções → Downloads:** caminho padrão `/media/downloads`.
4. **Opções → Conexão/Velocidade:** em máquina fraca, limite upload e conexões.
5. O `templates/qbittorrent/qBittorrent.conf` desativa `CSRFProtection` e `HostHeaderValidation` para o acesso na LAN funcionar. **Só use isso em rede local**, sem expor a porta na internet.

### 5.2 Prowlarr (`http://IP:9696`)
1. Crie usuário e senha na primeira abertura.
2. **Settings → Indexers → +** (tipo *Indexer Proxy*) → **FlareSolverr**: host `http://flaresolverr:8191`, tag `flaresolverr`. Aplique essa tag nos indexadores que passam pelo Cloudflare.
3. **Indexers → Add Indexer:** adicione os indexadores que você tem direito de usar (a lista de indexadores públicos e privados vem embutida). Faça **Test** em cada um.
4. Anote a **API Key** do Prowlarr: Settings → General.

### 5.3 Radarr (`http://IP:7878`) e Sonarr (`http://IP:8989`)
Faça o mesmo nos dois (Sonarr usa `/media/series` e a categoria `sonarr`).
1. Crie usuário e senha.
2. **Settings → Media Management → Root Folders:** `/media/filmes` (Radarr) ou `/media/series` (Sonarr). Sem espaço no início do caminho.
3. Confirme **Use Hardlinks instead of Copy** ligado.
4. **Settings → Download Clients → +  → qBittorrent:** host `qbittorrent`, porta `8080`, usuário/senha do passo 5.1, categoria `radarr` (ou `sonarr`). Teste.
5. Anote a **API Key** (Settings → General).

### 5.4 Ligar o Prowlarr aos apps
No Prowlarr: **Settings → Apps → + → Radarr** (e depois Sonarr):
- Prowlarr Server: `http://prowlarr:9696`
- Radarr Server: `http://radarr:7878` (Sonarr: `http://sonarr:8989`)
- API Key do Radarr/Sonarr
- **Sync Level: Full Sync**, e use **Sync App Indexers**.

Os indexadores aparecem sozinhos em Radarr/Sonarr (Settings → Indexers).

### 5.5 Perfil de qualidade e preferência por português (opcional)
Para preferir dublado em pt-BR e baixar inglês quando não houver:
1. **Settings → Custom Formats → Import** e cole o conteúdo de `templates/custom-formats/ptbr-dublado.json`. (Opcional: adicione uma condição de **Language = Portuguese (Brazil)** manualmente, porque o id do idioma muda entre versões.)
2. **Settings → Profiles →** seu perfil (ex.: HD-1080p):
   - **Language:** `Any` (se estiver em outro idioma, tudo é rejeitado: "X is wanted, but found Y")
   - Em **Custom Formats**, `PT-BR dublado` com pontuação `100`
   - **Minimum Custom Format Score:** `0` (aceita sem dublagem); `1` para só dublado
   - **Upgrade Until Custom Format Score:** `100`, com *Upgrades Allowed* ligado
3. O Radarr compara **qualidade antes da pontuação**. Para o idioma desempatar, agrupe qualidades equivalentes (por exemplo WEB 1080p + HDTV-1080p + Bluray-1080p) no mesmo grupo do perfil.
4. Teste: abra um filme → **Interactive Search**. Ícone vermelho = rejeitada; passe o mouse para ler o motivo.

### 5.6 Testar o ciclo completo
1. Radarr → **Add New**, busque um filme, Root Folder `/media/filmes`, Minimum Availability `Released`, marque **Start search for missing movie**, Add.
2. **Activity → Queue** mostra o download. No qBittorrent, o torrent aparece na categoria `radarr`.
3. Ao terminar, o Radarr importa para `/media/filmes/Nome (Ano)/`.

### 5.7 Bazarr (`http://IP:6767`)
1. **Settings → Languages:** crie um *Languages Profile* com **Portuguese (Brazil)** e defina como padrão para séries e filmes.
2. **Settings → Providers:** adicione os provedores de legenda que quiser (a maioria exige conta gratuita). Os provedores mudam com o tempo; remova os que falharem.
3. **Settings → Sonarr:** host `sonarr`, porta `8989`, API key do Sonarr. **Settings → Radarr:** host `radarr`, porta `7878`, API key do Radarr. Teste.
4. Sincronização automática de legendas (ffsubsync) usa **muita CPU** em arquivos grandes. Em máquina fraca, desligue-a em **Settings → Subtitles**.

### 5.8 Jellyfin (`http://IP:8096`)
1. Assistente inicial: crie o administrador.
2. **Bibliotecas:** Filmes → `/media/filmes`; Séries → `/media/series`.
3. **Painel → Reprodução → Transcodificação (aceleração por hardware)**, para GPU Intel: **Intel QuickSync (QSV)** ou **VAAPI**, dispositivo `/dev/dri/renderD128`. Marque os codecs suportados pelo seu processador. Sem GPU, deixe em *Nenhum* e remova as linhas `devices`/`group_add` do `compose.yaml`.
4. **Perfil de cada usuário → Reprodução:** idioma de áudio preferido `Português`.
5. Em **Painel → Bibliotecas**, ative o monitoramento em tempo real, se quiser que os filmes apareçam assim que forem importados.

### 5.9 Homepage (`http://IP:8082`)
Já vem com links para todos os serviços (copiados de `templates/homepage/`). Se aparecer erro "host validation failed", o endereço que você usou não está em `HOMEPAGE_ALLOWED_HOSTS` no `.env`: acrescente (separado por vírgula) e rode `docker compose up -d homepage`.
Widgets com números (downloads ativos, filmes na fila) exigem as API keys; veja a documentação do Homepage antes de colocá-las (as chaves ficam no `services.yaml` do host, **não** no repositório).

## 6. Extras que ficam fora do compose

- **Compartilhar a pasta de mídia na rede (Samba):**
  ```
  sudo apt install -y samba
  printf '\n[media]\n   path = /home/USUARIO/media\n   valid users = USUARIO\n   read only = no\n' | sudo tee -a /etc/samba/smb.conf
  sudo smbpasswd -a USUARIO && sudo systemctl restart smbd
  sudo ufw allow from 192.168.1.0/24 to any app Samba
  ```
  Windows: `\\IP\media`. Para arquivos grandes, SFTP (WinSCP/MobaXterm) costuma ser mais rápido no Wi-Fi.
- **Acesso fora de casa sem abrir portas:** instale o Tailscale no servidor (`curl -fsSL https://tailscale.com/install.sh | sh`, `sudo tailscale up`) e nos seus aparelhos. Libere a interface: `sudo ufw allow in on tailscale0`.
- **DNS com bloqueio de anúncios na rede (AdGuard Home):** fora do stack de propósito. Um erro nele derruba a navegação da casa. Instale à parte quando quiser.
- **Nomes locais** (`radarr.home.arpa` em vez de `IP:7878`): exigem DNS local e um proxy reverso (Caddy). Também fora do stack.
- **Backup das configurações:** `docs/restic.md`.
- **VPN para o qBittorrent:** não incluída. Se usar, ponha o qBittorrent atrás de um container de VPN (por exemplo gluetun) e guarde as credenciais em um arquivo `.env` separado, nunca no repositório.

## 7. Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| qBittorrent responde "Unauthorized" | Senha temporária mudou (veja o log) ou as opções de CSRF/Host não estão na seção `[WebUI]` do `qBittorrent.conf` |
| Radarr: "Invalid Path" na pasta raiz | Espaço no início ou pasta inexistente; use `/media/filmes` |
| Radarr não conecta no qBittorrent | Host deve ser `qbittorrent` e a porta `8080` (não `8081`, que é a do host) |
| Release com ícone vermelho na busca | Passe o mouse e leia o motivo (idioma do perfil, tamanho mínimo, seeders mínimos do indexador) |
| FlareSolverr: erro 500 / timeout | O site tem desafio do Cloudflare que não resolveu em 60 s; não é erro de configuração |
| Jellyfin não transcodifica por hardware | Sem `/dev/dri`, grupo errado (`RENDER_GID`) ou VAAPI/QSV não habilitado no painel |
| Container para sem memória | 4 GB é pouco: pare o Bazarr ou desligue a sincronização de legendas |
| Arquivos baixados com dono errado | Ajuste `PUID`/`PGID` no `.env` e recrie: `docker compose up -d` |
| Homepage: "host validation failed" | Inclua o endereço em `HOMEPAGE_ALLOWED_HOSTS` |

## 8. Atualizar

```
docker compose pull && docker compose up -d
docker image prune -f
```
Antes de atualizar, faça o backup das pastas em `${DATA}` (cada app também gera backups em *System → Backup*; eles contêm chaves de API, então não os publique).
