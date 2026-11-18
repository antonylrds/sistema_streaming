# Backup com Restic (servidor Debian 13)

O que salvar: as **configurações** dos apps (difíceis de refazer). Filmes e séries ficam de fora: o Radarr/Sonarr rebaixa o que for perdido.

## 0. Escolha o destino (um dos três)

| Opção | Protege contra | Observação |
|---|---|---|
| A. HD/SSD externo no servidor | falha do disco interno | mais simples; não protege contra roubo ou incêndio |
| B. Outro PC da casa (SFTP) | falha do servidor | precisa do outro PC ligado no horário |
| C. Nuvem (Backblaze B2) | tudo | poucos centavos por mês para ~1 GB |

Os passos 1 a 7 são iguais. Só o passo 2 muda.

## 1. Instalar

```
sudo apt install -y restic
restic version
```

## 2. Preparar o destino

### A. HD externo
```
lsblk -f                      # ache a partição e o UUID (ex.: sda1)
sudo mkdir -p /mnt/backup
echo 'UUID=COLE-O-UUID /mnt/backup ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a && sudo chown antony: /mnt/backup 2>/dev/null; sudo chown antony: /mnt/backup
```
(`nofail` evita que o servidor deixe de iniciar se o HD estiver desconectado. Se o disco for NTFS ou exFAT, prefira formatar em ext4: `sudo mkfs.ext4 /dev/sdX1`, o que apaga o disco.)

Repositório: `/mnt/backup/restic`

### B. Outro PC por SFTP
Gere uma chave só para isso e copie para o outro PC (Linux ou Windows com OpenSSH):
```
ssh-keygen -t ed25519 -f ~/.ssh/id_backup -N ''
ssh-copy-id -i ~/.ssh/id_backup.pub USUARIO@IP-DO-OUTRO-PC
```
Repositório: `sftp:USUARIO@IP-DO-OUTRO-PC:/caminho/restic`

### C. Backblaze B2
Crie um bucket **privado** e uma *Application Key* limitada a esse bucket. Guarde as chaves no arquivo do passo 3 (nunca no chat nem no GitHub).
Repositório: `b2:NOME-DO-BUCKET:restic`

## 3. Senha e variáveis

```
mkdir -p ~/.config/restic ~/bin
read -rs RP; printf '%s' "$RP" > ~/.config/restic/password; unset RP
chmod 600 ~/.config/restic/password
```
Digite a senha e tecle Enter (não aparece na tela). **Guarde essa senha fora do servidor** (gerenciador de senhas): sem ela, o backup não abre.

Crie `~/.config/restic/env` (troque a linha do repositório conforme o destino):
```
printf '%s\n' \
'export RESTIC_REPOSITORY=/mnt/backup/restic' \
'export RESTIC_PASSWORD_FILE=$HOME/.config/restic/password' \
> ~/.config/restic/env
chmod 600 ~/.config/restic/env
```
Para B2, acrescente `export B2_ACCOUNT_ID=...` e `export B2_ACCOUNT_KEY=...`. Para SFTP, o repositório é `sftp:...` e use `-o sftp.command='ssh -i ~/.ssh/id_backup USUARIO@IP -s sftp'` se a chave padrão não servir.

## 4. Criar o repositório

```
. ~/.config/restic/env
restic init
```

## 5. Script de backup

```
printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'. "$HOME/.config/restic/env"' \
'restic backup \' \
'  "$HOME/radarr" "$HOME/sonarr" "$HOME/prowlarr" "$HOME/bazarr" \' \
'  "$HOME/qbittorrent" "$HOME/jellyfin" "$HOME/homepage" "$HOME/adguard" \' \
'  "$HOME/.config/containers/systemd" \' \
'  --exclude "*/MediaCover" --exclude "*/cache" --exclude "*/transcodes" \' \
'  --exclude "*/log" --exclude "*/logs" --exclude "*/metadata" \' \
'  --tag servidor' \
'restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune' \
> ~/bin/backup.sh
chmod +x ~/bin/backup.sh
```
Notas:
- `MediaCover` (posters do Radarr/Sonarr) e `metadata` (imagens do Jellyfin) são grandes e se refazem sozinhos.
- Bancos SQLite copiados com o app rodando quase sempre ficam íntegros. Para ter certeza, os apps também fazem backup próprio em `config/Backups` (que entra no backup). Se quiser zero risco, adicione `systemctl --user stop radarr sonarr prowlarr bazarr` antes do `restic backup` e `start` depois.
- `forget --prune` guarda 7 diários, 4 semanais e 6 mensais.

Teste:
```
~/bin/backup.sh
. ~/.config/restic/env && restic snapshots
```

## 6. Agendar (timer do systemd)

```
printf '%s\n' \
'[Unit]' \
'Description=Backup restic' \
'' \
'[Service]' \
'Type=oneshot' \
'ExecStart=%h/bin/backup.sh' \
'Nice=19' \
'IOSchedulingClass=idle' \
> ~/.config/systemd/user/restic-backup.service

printf '%s\n' \
'[Unit]' \
'Description=Backup restic diario' \
'' \
'[Timer]' \
'OnCalendar=*-*-* 04:00:00' \
'Persistent=true' \
'RandomizedDelaySec=15m' \
'' \
'[Install]' \
'WantedBy=timers.target' \
> ~/.config/systemd/user/restic-backup.timer

systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer
systemctl --user list-timers | grep restic
```
(Se a pasta `~/.config/systemd/user` não existir: `mkdir -p ~/.config/systemd/user`. O linger já está ativo, então roda sem sessão aberta.)

Ver o resultado da última execução: `journalctl --user -u restic-backup -n 30 --no-pager`

## 7. Restaurar (teste isso uma vez, para valer)

```
. ~/.config/restic/env
restic snapshots
restic restore latest --target /tmp/teste-restore --include "$HOME/radarr"
ls /tmp/teste-restore
```
Restaurar de verdade num servidor novo: pare os containers, restaure para `/` com `restic restore latest --target /` e suba os containers de novo.

Verificação periódica da integridade (mensal): `restic check`.

## Checklist

- [ ] Destino montado (A) / chave SSH (B) / bucket e chave (C)
- [ ] Senha guardada fora do servidor
- [ ] `restic init` feito
- [ ] `~/bin/backup.sh` rodou e há um snapshot
- [ ] Timer ativo (`list-timers`)
- [ ] Restauração de teste feita
- [ ] Nada disso foi enviado ao GitHub (a senha, o `env` e as chaves ficam fora do repositório)
