#!/usr/bin/env bash
#
# backup-avulso.sh
# Envia os arquivos de uma pasta sua para uma pasta do Google Drive.
#
# O que faz, em ordem:
#   1. lista os arquivos da pasta que voce indicou
#   2. pergunta o nome da pasta que vai ser criada no Google Drive
#   3. cria essa pasta no Drive
#   4. envia um arquivo por vez, e confere cada um no destino
#   5. escreve um relatorio do que subiu, do que foi pulado e do que falhou
#
# Uso:
#   ./backup-avulso.sh /caminho/da/pasta
#
# Ajuda:
#   ./backup-avulso.sh --ajuda
#
# Nao precisa criar projeto no Google Cloud, nem chave, nem faturamento. A
# autorizacao usa a chave que ja vem embutida no rclone.

set -Eeuo pipefail

# Array associativo, mapfile e ${var,,} sao de bash 4. O bash do macOS e o 3.2,
# de 2007, e la o script quebraria no meio com erro que nao explica nada. Melhor
# dizer na primeira linha o que falta.
if [[ -z "${BASH_VERSINFO:-}" ]] || ((BASH_VERSINFO[0] < 4)); then
  printf 'ERRO: este script precisa de bash 4 ou mais novo (aqui e o %s).
' "${BASH_VERSION:-desconhecido}" >&2
  printf '      no macOS:  brew install bash  e rode com  /opt/homebrew/bin/bash %s
' "$0" >&2
  exit 1
fi

VERSAO_SCRIPT="1.0.0"
NOME_SCRIPT="$(basename "$0")"

# ---------------------------------------------------------------------------
# Opcoes
# ---------------------------------------------------------------------------
ORIGEM=""
DRIVE_PASTA=""
SEM_SUBPASTAS=0
SEM_OCULTOS=0
SEGUIR_ATALHOS=0
MAX_MB=0                     # 0 = sem limite
declare -a INCLUIR=()
declare -a EXCLUIR=()
CIFRAR=0
ARQUIVO_SENHA=""
SIMULAR=0
SIM=0
SEM_NICE=0
REFAZER=0
SO_REGISTRO=0
SO_CONECTAR=0
RECONECTAR=0
ESTADO_PEDIDO=""
DRIVE_REMOTE="avulso-drive"
DRIVE_ESCOPO="total"
POR_DATA=0
DRIVE_MANTER=0

# ---------------------------------------------------------------------------
# Estado interno
# ---------------------------------------------------------------------------
INICIO_EPOCH="$(date +%s)"
CARIMBO="$(date +%Y%m%d-%H%M%S)"
PASTA_DATA="$(date +%Y-%m-%d_%H%M)"
LOG=""
TMP=""
TRAVA=""
ESTADO=""
REGISTRO=""
RELATORIO=""
PASTA_DRIVE=""
declare -a ARQUIVOS=()        # caminhos relativos a ORIGEM
declare -a ATALHOS=()
declare -a VAZIAS=()
declare -a FORA=()            # relativo|motivo
declare -a AVISOS=()
declare -a ERROS=()
declare -a LINHAS_RELATORIO=()
declare -A TAMANHO_DE=()
CORES=0
OK_ARQ=0
FALHA_ARQ=0
PULADOS=0
BYTES_TOTAL=0
BYTES_ENVIADOS=0
CONFERENCIA=""                # MD5 | tamanho
CONFERENCIA_POR_TAMANHO=0
PASTA_DRIVE_JA_EXISTIA=0

# ---------------------------------------------------------------------------
# Saida
# ---------------------------------------------------------------------------
cor() { if ((CORES)); then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
agora() { date '+%H:%M:%S'; }
diz()   { printf '%s %s\n' "$(cor '0;90' "[$(agora)]")" "$*"; }
passo() { printf '\n%s %s\n' "$(cor '1;36' '==>')" "$(cor '1' "$*")"; }
feito() { printf '%s %s\n' "$(cor '0;32' '  ok')" "$*"; }
aviso() { AVISOS+=("$*"); printf '%s %s\n' "$(cor '1;33' '  !!')" "$*"; }
falha() { ERROS+=("$*");  printf '%s %s\n' "$(cor '1;31' '  xx')" "$*"; }
morre() { printf '\n%s %s\n' "$(cor '1;31' 'ERRO:')" "$*" >&2; exit 1; }

if [[ -t 1 ]]; then CORES=1; fi

ajuda() {
  cat <<AJUDA
$NOME_SCRIPT v$VERSAO_SCRIPT

Envia os arquivos de uma pasta sua para uma pasta do Google Drive. Um arquivo
por vez: envia, confere no destino, segue para o proximo.

USO
  ./$NOME_SCRIPT /caminho/da/pasta

  O script lista os arquivos dessa pasta, pergunta o nome da pasta que vai
  ser criada no Google Drive, e envia. So isso.

PRIMEIRA VEZ
  Na primeira execucao ele mesmo liga o Google Drive: mostra um link, voce
  abre no navegador, escolhe a conta Google, clica em Permitir, copia a URL em
  que o navegador caiu e cola de volta aqui. Acabou.
  Nao precisa criar projeto no Google Cloud, nem chave, nem faturamento: a
  autorizacao usa a chave que ja vem embutida no rclone.

  Para ligar o Drive sem fazer backup nenhum:
      ./$NOME_SCRIPT --conectar

OPCOES
  -p, --pasta DIR       A pasta de origem, se voce preferir nomear a opcao.
      --drive-pasta P   Nome da pasta no Google Drive, para nao ser perguntado.
                        Aceita caminho: Backups/Fotos cria as duas.
      --sem-subpastas   So os arquivos que estao na raiz da pasta. Padrao:
                        entra nas subpastas e repete a estrutura no Drive.
      --sem-ocultos     Deixa de fora arquivo e pasta que comecam com ponto.
      --incluir PADRAO  So arquivos que casam com o padrao. Pode repetir.
                        Exemplo: --incluir '*.pdf' --incluir '*.jpg'
      --excluir PADRAO  Deixa de fora quem casa com o padrao. Pode repetir.
                        Exemplo: --excluir '*.tmp' --excluir 'node_modules/*'
      --max-mb N        Pula arquivo maior que N MB, e diz no relatorio.
      --seguir-atalhos  Envia o conteudo apontado pelo atalho simbolico.
                        Padrao: atalho fica de fora e aparece no relatorio.
      --cifrar          Cifra cada arquivo antes de subir. Gera .gpg no Drive.
      --senha-arquivo F Le a senha da cifra do arquivo F em vez de perguntar.
      --simular         Lista o que seria enviado, com tamanho e total. Nao
                        envia nada e nao cria pasta no Drive.
  -s, --sim             Responde sim as perguntas (uso no cron).
      --sem-nice        Roda em prioridade normal de CPU e disco. Padrao:
                        prioridade baixa, para nao travar a maquina.
  -h, --ajuda           Esta ajuda.

RODAR DE NOVO NA MESMA PASTA
  Toda vez que um arquivo sobe, ele deixa uma linha no registro. Na execucao
  seguinte, arquivo que nao mudou e pulado, arquivo que mudou sobe de novo, e
  arquivo novo sobe. Entao, se a execucao morrer no arquivo 300 de 900, basta
  rodar o mesmo comando outra vez.

      --registro        Mostra o que ja foi enviado desta pasta, e sai.
      --refazer         Envia tudo de novo, mesmo o que nao mudou.
      --estado DIR      Onde ficam o registro, o log e o relatorio.
                        Padrao: \$HOME/.backup-avulso/<pasta-no-drive>-<id>
                        A pasta de origem nunca e tocada: nada e escrito,
                        movido ou apagado dentro dela.

GOOGLE DRIVE
      --conectar        Liga o Drive e sai, sem backup.
      --reconectar      Refaz a autorizacao mesmo se ja existir uma.
      --drive-remote N  Nome do remote no rclone. Padrao: $DRIVE_REMOTE
      --drive-escopo E  'total' (padrao) ou 'arquivos'. Com 'arquivos' o acesso
                        fica so no que o proprio script cria, e ai ele nao
                        enxerga pasta que voce criou a mao no Drive.
      --por-data        Guarda historico: cada execucao vai para
                        <pasta>/AAAA-MM-DD_HHMM/... Sem isso o arquivo e
                        substituido, e existe sempre a copia mais nova, so ela.
      --drive-manter N  Com --por-data, guarda as N pastas de data mais novas
                        e apaga as mais antigas. Padrao 0, que nao apaga nada.

EXEMPLOS
  ./$NOME_SCRIPT ~/Documentos
  ./$NOME_SCRIPT ~/Fotos --drive-pasta Fotos-2026 -s
  ./$NOME_SCRIPT /var/www --excluir 'node_modules/*' --excluir '*.log'
  ./$NOME_SCRIPT ~/Documentos --simular

AGENDAR, DEPOIS DE JA TER CONECTADO UMA VEZ
  30 2 * * * /caminho/$NOME_SCRIPT /caminho/da/pasta --drive-pasta MeuBackup -s >> /tmp/backup-avulso.log 2>&1
AJUDA
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
while (($#)); do
  case "$1" in
    -p|--pasta)        ORIGEM="${2:?caminho}"; shift 2 ;;
    --drive-pasta)     DRIVE_PASTA="${2:?nome}"; shift 2 ;;
    --sem-subpastas)   SEM_SUBPASTAS=1; shift ;;
    --sem-ocultos)     SEM_OCULTOS=1; shift ;;
    --incluir)         INCLUIR+=("${2:?padrao}"); shift 2 ;;
    --excluir)         EXCLUIR+=("${2:?padrao}"); shift 2 ;;
    --max-mb)          MAX_MB="${2:?numero}"; shift 2 ;;
    --seguir-atalhos)  SEGUIR_ATALHOS=1; shift ;;
    --cifrar)          CIFRAR=1; shift ;;
    --senha-arquivo)   ARQUIVO_SENHA="${2:?arquivo}"; CIFRAR=1; shift 2 ;;
    --simular)         SIMULAR=1; shift ;;
    -s|--sim)          SIM=1; shift ;;
    --sem-nice)        SEM_NICE=1; shift ;;
    --refazer)         REFAZER=1; shift ;;
    --registro)        SO_REGISTRO=1; shift ;;
    --estado)          ESTADO_PEDIDO="${2:?caminho}"; shift 2 ;;
    --conectar)        SO_CONECTAR=1; shift ;;
    --reconectar)      RECONECTAR=1; SO_CONECTAR=1; shift ;;
    --drive-remote)    DRIVE_REMOTE="${2:?nome}"; shift 2 ;;
    --drive-escopo)    DRIVE_ESCOPO="${2:?escopo}"; shift 2 ;;
    --por-data)        POR_DATA=1; shift ;;
    --drive-manter)    DRIVE_MANTER="${2:?numero}"; shift 2 ;;
    -h|--ajuda|--help) ajuda; exit 0 ;;
    -*) morre "opcao desconhecida: $1 (use --ajuda)" ;;
    *)  if [[ -z "$ORIGEM" ]]; then ORIGEM="$1"; shift
        else morre "so uma pasta de origem por execucao (recebi '$ORIGEM' e '$1')"; fi ;;
  esac
done

[[ "$MAX_MB" =~ ^[0-9]+$ ]]       || morre "--max-mb precisa ser um numero"
[[ "$DRIVE_MANTER" =~ ^[0-9]+$ ]] || morre "--drive-manter precisa ser um numero"
case "$DRIVE_ESCOPO" in total|arquivos) ;; *) morre "--drive-escopo aceita 'total' ou 'arquivos'" ;; esac
if ((DRIVE_MANTER > 0)) && ((POR_DATA == 0)); then
  morre "--drive-manter so faz sentido com --por-data (sem --por-data nao existe historico para rodar)"
fi

# O registro, o log e o relatorio dizem quais arquivos voce tem e para onde
# eles foram. Nascem 600, em vez de nascer 644 e virar 600 no chmod de depois:
# nesse meio tempo qualquer usuario da maquina leria.
umask 077

# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------
tem() { command -v "$1" >/dev/null 2>&1; }

legivel() {
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN{
    s="B KB MB GB TB PB"; split(s,u," "); i=1;
    while (b>=1024 && i<6) { b/=1024; i++ }
    printf (i==1 ? "%d %s" : "%.1f %s"), b, u[i]
  }'
}

# stat muda de sintaxe entre GNU e BSD, e esta pasta pode estar num Mac
tamanho_arquivo() {
  [[ -f "$1" ]] || { echo 0; return 0; }
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}
mtime_de() {
  [[ -e "$1" ]] || { echo 0; return 0; }
  stat -c%Y "$1" 2>/dev/null || stat -f%m "$1" 2>/dev/null || echo 0
}

espaco_livre() {
  local v=""
  v="$(df -P "$1" 2>/dev/null | awk 'NR==2{print ($4+0)*1024; exit}')" || v=""
  [[ -n "$v" ]] || v=0
  printf '%s\n' "$v"
}

# sort -z e do GNU. No BSD ele nao existe, e ai a lista vai na ordem do find,
# que continua correta, so nao fica alfabetica.
SORT_Z=""
if printf '' | sort -z >/dev/null 2>&1; then SORT_Z="sim"; fi
ordena_z() { if [[ -n "$SORT_Z" ]]; then sort -z; else cat; fi; }

md5_local() {
  if tem md5sum; then md5sum "$1" | awk '{print $1}'; return 0; fi
  if tem md5;    then md5 -q "$1"; return 0; fi
  printf ''
}

# -r /dev/tty so diz se o no tem permissao de leitura, e responde que sim mesmo
# quando o processo nao tem terminal de controle, como no cron. O jeito honesto
# e tentar abrir o dispositivo.
tem_terminal() { ( exec 3<>/dev/tty ) 2>/dev/null; }

pergunta_sim() {
  local r=""
  ((SIM)) && return 0
  tem_terminal || return 1
  printf '  %s [s/N] ' "$1" > /dev/tty
  read -r r < /dev/tty || true
  [[ "$r" == [sS]* ]]
}

le_do_tty() {  # le_do_tty "rotulo" [oculto]
  local r=""
  tem_terminal || return 1
  printf '  %s: ' "$1" > /dev/tty
  if [[ "${2:-}" == "oculto" ]]; then
    read -r -s r < /dev/tty || true
    printf '\n' > /dev/tty
  else
    read -r r < /dev/tty || true
  fi
  printf '%s' "$r"
}

na_saida() {
  local st=$?
  trap - EXIT INT TERM
  [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
  exit "$st"
}

# id curto e estavel da pasta de origem, para dois backups de pastas diferentes
# com o mesmo nome no Drive nao dividirem o mesmo registro
id_da_origem() {
  local caminho="$1" h=""
  if tem sha1sum;   then h="$(printf '%s' "$caminho" | sha1sum   | cut -c1-8)"
  elif tem shasum;  then h="$(printf '%s' "$caminho" | shasum    | cut -c1-8)"
  elif tem md5sum;  then h="$(printf '%s' "$caminho" | md5sum    | cut -c1-8)"
  elif tem cksum;   then h="$(printf '%s' "$caminho" | cksum | awk '{printf "%08x", $1}')"
  fi
  [[ -n "$h" ]] || h="semid"
  printf '%s' "$h"
}

# tira do nome da pasta do Drive o que nao serve como nome de pasta local
apelido() {
  printf '%s' "$1" | tr '/\\: ' '----' | tr -cd 'A-Za-z0-9._-' | cut -c1-40
}

# ---------------------------------------------------------------------------
# Google Drive
#
# O transporte e o rclone. A autorizacao usa a chave que ja vem embutida nele:
# nao precisa de projeto no Google Cloud, nem de faturamento, nem de aprovacao.
# O token fica em rclone.conf com permissao 600, e o rclone renova o acesso
# sozinho depois, sem pedir nada de novo.
# ---------------------------------------------------------------------------
instala_rclone() {
  tem rclone && return 0
  passo "Instalando o rclone (transporte para o Google Drive)"
  # pacote da distribuicao primeiro, porque vem assinado pelo repositorio
  if tem apt-get && [[ $EUID -eq 0 ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y rclone >>"$LOG" 2>&1 && tem rclone && {
      feito "rclone instalado pelo apt"; return 0; }
  elif tem dnf && [[ $EUID -eq 0 ]]; then
    dnf install -y rclone >>"$LOG" 2>&1 && tem rclone && { feito "rclone instalado pelo dnf"; return 0; }
  elif tem yum && [[ $EUID -eq 0 ]]; then
    yum install -y rclone >>"$LOG" 2>&1 && tem rclone && { feito "rclone instalado pelo yum"; return 0; }
  elif tem brew; then
    brew install rclone >>"$LOG" 2>&1 && tem rclone && { feito "rclone instalado pelo brew"; return 0; }
  fi
  aviso "o gerenciador de pacotes nao tinha o rclone, ou faltou permissao"
  printf '\n  O jeito oficial de instalar e baixar e rodar o script do site do rclone:\n'
  printf '    curl https://rclone.org/install.sh | sudo bash\n\n'
  printf '  Isso baixa e executa um script de rclone.org nesta maquina.\n'
  if pergunta_sim "Autoriza esse download e execucao?"; then
    tem curl || { falha "preciso do curl para baixar o instalador"; return 1; }
    local comsudo=""
    [[ $EUID -eq 0 ]] || comsudo="sudo"
    if curl -fsSL https://rclone.org/install.sh 2>>"$LOG" | ${comsudo:+$comsudo} bash >>"$LOG" 2>&1 && tem rclone; then
      feito "rclone $(rclone version 2>/dev/null | head -1 | awk '{print $2}') instalado"
      return 0
    fi
    falha "a instalacao do rclone nao terminou (veja $LOG)"
    return 1
  fi
  falha "sem rclone nao da para enviar ao Drive. Instale a mao e rode de novo."
  return 1
}

arquivo_conf_rclone() {
  local c=""
  c="$(rclone config file 2>/dev/null | tail -1 | tr -d '\r')" || c=""
  [[ -n "$c" ]] || c="$HOME/.config/rclone/rclone.conf"
  printf '%s' "$c"
}

remote_ja_existe() {
  rclone listremotes 2>/dev/null | grep -qx "${DRIVE_REMOTE}:"
}

testa_remote() {
  rclone lsd "${DRIVE_REMOTE}:" >/dev/null 2>>"$LOG"
}

# Escreve a secao do remote no rclone.conf sem apagar o que ja esta la.
escreve_remote_rclone() {
  local token="$1" escopo="${2:-}"
  local conf; conf="$(arquivo_conf_rclone)"
  mkdir -p "$(dirname "$conf")" && chmod 700 "$(dirname "$conf")" 2>/dev/null || true
  if [[ -f "$conf" ]]; then
    cp -p "$conf" "$conf.antes-$CARIMBO" 2>/dev/null || true
    # remove uma secao com o mesmo nome, se houver, preservando as outras
    awk -v alvo="[$DRIVE_REMOTE]" '
      /^\[/ { dentro = ($0 == alvo) }
      !dentro { print }
    ' "$conf" > "$conf.novo" && mv "$conf.novo" "$conf"
  fi
  umask 077
  # separa da secao anterior quando o arquivo nao termina em linha em branco
  if [[ -s "$conf" ]] && [[ -n "$(tail -c 2 "$conf" | tr -d '\n')" ]]; then
    printf '\n' >> "$conf"
  fi
  {
    printf '[%s]\n' "$DRIVE_REMOTE"
    printf 'type = drive\n'
    # client_id e client_secret ficam de fora de proposito: assim o rclone usa
    # a chave que vem embutida nele, inclusive para renovar o acesso. Gravar
    # campo vazio faria a renovacao falhar depois.
    [[ -n "$escopo" ]] && printf 'scope = %s\n' "$escopo"
    printf 'token = %s\n' "$token"
    printf '\n'
  } >> "$conf"
  chmod 600 "$conf"
  feito "remote '$DRIVE_REMOTE' gravado em $conf"
}

escopo_conf() {
  case "$DRIVE_ESCOPO" in
    arquivos) printf 'drive.file' ;;
    *)        printf 'drive' ;;
  esac
}
escopo_codificado() {
  case "$DRIVE_ESCOPO" in
    arquivos) printf 'https%%3A%%2F%%2Fwww.googleapis.com%%2Fauth%%2Fdrive.file' ;;
    *)        printf 'https%%3A%%2F%%2Fwww.googleapis.com%%2Fauth%%2Fdrive' ;;
  esac
}

# pega o valor de uma chave de texto no JSON, sem depender de jq
valor_json() {
  printf '%s' "$1" | tr -d '\n\r' \
    | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}
numero_json() {
  printf '%s' "$1" | tr -d '\n\r' \
    | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\).*/\1/p" | head -1
}

# ---------------------------------------------------------------------------
# Autorizacao: um link, e a URL de volta. So isso.
#
# O script monta o link, voce abre no navegador, escolhe a conta Google e clica
# em Permitir. O Google devolve o navegador para 127.0.0.1:53682, que nao tem
# ninguem escutando, entao a pagina da erro. Isso e o esperado: o que importa
# esta na barra de endereco. Voce copia a URL inteira, cola aqui, e o script
# troca o codigo dela por um token.
#
# A chave usada e a que ja vem embutida no proprio rclone, publicada no codigo
# dele. Credencial de aplicativo instalado nao e confidencial por desenho, e e
# por usar essa que nao existe projeto no Google Cloud para criar, nem
# faturamento, nem tela de verificacao. O token gravado sai sem client_id e sem
# client_secret, para o rclone renovar o acesso com a chave dele mesmo.
# ---------------------------------------------------------------------------
CLIENTE_RCLONE="202264815644.apps.googleusercontent.com"
SEGREDO_RCLONE="X4Z3ca8xfWDb1Voo-F9a7ZxJ"
REDIRECIONAMENTO="http://127.0.0.1:53682/"
REDIRECIONAMENTO_CODIFICADO="http%3A%2F%2F127.0.0.1%3A53682%2F"

autoriza_por_link() {
  local id="$CLIENTE_RCLONE" segredo="$SEGREDO_RCLONE"

  # PKCE quando houver openssl. Protege a troca do codigo pelo token.
  local verificador="" desafio="" parte_pkce=""
  if tem openssl; then
    verificador="$(openssl rand -base64 48 2>/dev/null | tr -d '\n\r=' | tr '+/' '-_')"
    desafio="$(printf '%s' "$verificador" | openssl dgst -binary -sha256 2>/dev/null \
               | openssl base64 2>/dev/null | tr -d '\n\r=' | tr '+/' '-_')"
    if [[ -n "$verificador" && -n "$desafio" ]]; then
      parte_pkce="&code_challenge=$desafio&code_challenge_method=S256"
    else
      verificador=""
    fi
  fi

  local url
  url="https://accounts.google.com/o/oauth2/v2/auth?client_id=${id}"
  url="${url}&redirect_uri=${REDIRECIONAMENTO_CODIFICADO}&response_type=code"
  url="${url}&scope=$(escopo_codificado)&access_type=offline&prompt=consent${parte_pkce}"

  {
    printf '\n'
    printf '  ABRA ESTE LINK NO NAVEGADOR DO SEU COMPUTADOR:\n\n'
    printf '%s\n\n' "$url"
    printf '  1. escolha a conta Google onde o backup vai ficar;\n'
    printf '  2. se aparecer aviso de aplicativo nao verificado, clique em\n'
    printf '     Avancado e depois em Acessar;\n'
    printf '  3. clique em Permitir;\n'
    printf '  4. a pagina seguinte vai dizer que nao conseguiu acessar\n'
    printf '     127.0.0.1. E isso mesmo, nao deu errado: o endereco dela E a\n'
    printf '     sua resposta. Copie a barra de endereco INTEIRA e cole aqui.\n\n'
    printf '  A URL comeca com %s e tem code= no meio.\n\n' "$REDIRECIONAMENTO"
  } > /dev/tty

  local colado codigo
  colado="$(le_do_tty 'Cole a URL completa')"
  codigo="$(printf '%s' "$colado" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' | head -1)"
  [[ -n "$codigo" ]] || codigo="$(printf '%s' "$colado" | tr -d '[:space:]')"
  if [[ -z "$codigo" ]]; then
    falha "nao achei o code= no que voce colou"
    aviso "cole a URL inteira da barra de endereco, a que comeca com $REDIRECIONAMENTO"
    return 1
  fi
  case "$colado" in
    *error=access_denied*) falha "a autorizacao foi recusada na tela do Google"; return 1 ;;
    *error=*)              falha "o Google devolveu um erro na URL: ${colado#*error=}"; return 1 ;;
  esac
  codigo="$(printf '%s' "$codigo" | sed 's/%2F/\//g; s/%2f/\//g')"

  # troca o codigo pelo token. Tudo por arquivo, para o segredo e o token nao
  # aparecerem na linha de comando da maquina.
  diz "trocando o codigo por um token"
  local d resposta acesso atualizacao segundos expiracao erro
  d="$(mktemp -d)"; chmod 700 "$d"
  umask 077
  printf '%s' "$codigo"           > "$d/code"
  printf '%s' "$id"               > "$d/id"
  printf '%s' "$segredo"          > "$d/secret"
  printf '%s' "$REDIRECIONAMENTO" > "$d/redirect"
  [[ -n "$verificador" ]] && printf '%s' "$verificador" > "$d/verifier"

  declare -a extra=()
  [[ -n "$verificador" ]] && extra=(--data-urlencode "code_verifier@$d/verifier")

  resposta="$(curl -fsS --max-time 60 https://oauth2.googleapis.com/token \
    --data-urlencode "code@$d/code" \
    --data-urlencode "client_id@$d/id" \
    --data-urlencode "client_secret@$d/secret" \
    --data-urlencode "redirect_uri@$d/redirect" \
    ${extra[@]+"${extra[@]}"} \
    -d grant_type=authorization_code 2>>"$LOG")" || resposta=""
  rm -rf "$d"

  if [[ -z "$resposta" ]]; then
    falha "o Google nao aceitou a troca do codigo pelo token"
    aviso "o codigo vale poucos minutos. Rode --conectar de novo e cole a URL logo depois de autorizar."
    return 1
  fi

  erro="$(valor_json "$resposta" error)"
  if [[ -n "$erro" ]]; then
    falha "o Google recusou: $erro"
    [[ "$erro" == "invalid_grant" ]] && aviso "o codigo ja foi usado ou venceu. Autorize de novo e cole a URL na hora."
    return 1
  fi

  acesso="$(valor_json "$resposta" access_token)"
  atualizacao="$(valor_json "$resposta" refresh_token)"
  segundos="$(numero_json "$resposta" expires_in)"
  [[ -n "$segundos" ]] || segundos=3600

  if [[ -z "$acesso" ]]; then
    falha "a resposta do Google nao trouxe access_token"
    return 1
  fi
  if [[ -z "$atualizacao" ]]; then
    falha "a resposta do Google nao trouxe refresh_token, entao o envio pararia de funcionar em uma hora"
    aviso "isso acontece quando esta conta ja autorizou antes. Remova o acesso em myaccount.google.com/permissions e autorize de novo."
    return 1
  fi

  expiracao="$(date -u -d "+${segundos} seconds" '+%Y-%m-%dT%H:%M:%S.000000000Z' 2>/dev/null)" \
    || expiracao="$(date -u '+%Y-%m-%dT%H:%M:%S.000000000Z')"

  escreve_remote_rclone \
    "{\"access_token\":\"$acesso\",\"token_type\":\"Bearer\",\"refresh_token\":\"$atualizacao\",\"expiry\":\"$expiracao\"}" \
    "$(escopo_conf)"
  return 0
}

configura_drive() {
  passo "Conectando o Google Drive"

  instala_rclone || return 1

  if remote_ja_existe && ((RECONECTAR == 0)); then
    if testa_remote; then
      feito "o remote '$DRIVE_REMOTE' ja esta conectado e respondendo"
      return 0
    fi
    aviso "o remote '$DRIVE_REMOTE' existe mas nao responde, vou refazer a autorizacao"
  fi

  if ! tem_terminal; then
    falha "a primeira autorizacao do Drive precisa de terminal, porque alguem clica em Permitir"
    aviso "rode uma vez na mao: ./$NOME_SCRIPT --conectar. Depois disso o backup roda sozinho no cron."
    return 1
  fi
  tem curl || { falha "preciso do curl para trocar o codigo pelo token"; return 1; }

  autoriza_por_link || return 1

  diz "testando a conexao"
  if testa_remote; then
    feito "Google Drive conectado"
    return 0
  fi
  falha "o remote foi gravado mas o Drive nao respondeu (veja $LOG)"
  return 1
}

opcoes_rclone() {
  printf '%s\n' \
    --config "$(arquivo_conf_rclone)" \
    --drive-chunk-size 64M \
    --retries 5 --low-level-retries 20 \
    --stats 20s --stats-one-line \
    --log-level INFO --log-file "$LOG"
}

# Nome de pasta no Drive: o que o Google e o rclone aceitam, e nada que faca o
# caminho virar outra coisa.
valida_nome_drive() {
  local n="$1"
  [[ -n "$n" ]]                      || { printf 'o nome nao pode ser vazio'; return 1; }
  case "$n" in
    *:*)   printf "o nome nao pode ter ':', que o rclone usa para separar o remote"; return 1 ;;
    /*)    printf 'o nome nao pode comecar com /'; return 1 ;;
    *..*)  printf "o nome nao pode ter '..'"; return 1 ;;
    *'\'*) printf 'o nome nao pode ter barra invertida'; return 1 ;;
  esac
  [[ "$n" != *$'\n'* && "$n" != *$'\t'* ]] || { printf 'o nome nao pode ter quebra de linha nem tabulacao'; return 1; }
  return 0
}

pede_nome_da_pasta() {
  local sugestao padrao n motivo
  sugestao="$(basename "$ORIGEM")"
  padrao="$(printf '%s' "$sugestao" | tr -cd 'A-Za-z0-9._ -' | sed 's/^ *//; s/ *$//')"
  [[ -n "$padrao" ]] || padrao="backup"

  if ! tem_terminal; then
    DRIVE_PASTA="$padrao"
    aviso "sem terminal para perguntar, vou usar a pasta '$DRIVE_PASTA' no Drive (use --drive-pasta para escolher)"
    return 0
  fi

  {
    printf '\n'
    printf '  Que nome vai ter a pasta criada no seu Google Drive?\n'
    printf '  Enter aceita: %s\n' "$padrao"
  } > /dev/tty

  while :; do
    n="$(le_do_tty 'Nome da pasta no Drive')"
    [[ -n "$n" ]] || n="$padrao"
    n="${n#/}"; n="${n%/}"
    if motivo="$(valida_nome_drive "$n")"; then
      DRIVE_PASTA="$n"
      return 0
    fi
    printf '  %s. Tente de novo.\n' "$motivo" > /dev/tty
  done
}

# Cria a pasta no Drive, e diz quando ela ja existia.
cria_pasta_drive() {
  local base="${DRIVE_REMOTE}:${DRIVE_PASTA}" quantos=""
  quantos="$(rclone size --config "$(arquivo_conf_rclone)" --json "$base" 2>>"$LOG" \
             | sed -n 's/.*"count":[[:space:]]*\([0-9]\{1,\}\).*/\1/p' | head -1)" || quantos=""
  if [[ -n "$quantos" ]]; then
    PASTA_DRIVE_JA_EXISTIA=1
    if ((quantos > 0)); then
      aviso "a pasta '$DRIVE_PASTA' ja existe no Drive, com $quantos arquivo(s) dentro"
      if ! pergunta_sim "Usar essa mesma pasta? Arquivo de mesmo nome vai ser substituido."; then
        morre "nada foi enviado. Rode de novo com --drive-pasta OUTRONOME."
      fi
    else
      diz "a pasta '$DRIVE_PASTA' ja existe no Drive e esta vazia"
    fi
  fi
  if rclone mkdir --config "$(arquivo_conf_rclone)" --log-level ERROR --log-file "$LOG" "$base" 2>>"$LOG"; then
    ((PASTA_DRIVE_JA_EXISTIA)) || feito "pasta '$DRIVE_PASTA' criada no Google Drive"
    return 0
  fi
  falha "nao consegui criar a pasta '$DRIVE_PASTA' no Drive (veja $LOG)"
  return 1
}

# envia_arquivo <arquivo local> <caminho no destino, relativo a PASTA_DRIVE>
#
# Devolve 0 so quando o arquivo no Drive confere com o daqui. A conferencia
# tenta o conteudo primeiro: o Google Drive guarda e devolve o MD5 de cada
# arquivo, e o rclone le esse valor, entao da para comparar sem baixar nada.
# MD5 aqui e conferencia de integridade, nao de seguranca: serve para pegar
# arquivo truncado ou byte trocado no caminho.
# Quando o Drive nao devolve hash, sobra a comparacao de tamanho, e o relatorio
# diz qual das duas foi usada, para ninguem achar que teve mais garantia do que
# teve.
MD5_ENVIADO=""
envia_arquivo() {
  local arquivo="$1" nome="$2"
  local local_bytes remoto md5l md5r
  declare -a opcoes=()
  mapfile -t opcoes < <(opcoes_rclone)
  MD5_ENVIADO=""

  local_bytes="$(tamanho_arquivo "$arquivo")"
  if ! rclone copyto "${opcoes[@]}" "$arquivo" "$PASTA_DRIVE/$nome"; then
    falha "$nome: o envio para o Drive falhou (veja $LOG)"
    return 1
  fi

  remoto="$(rclone size --config "$(arquivo_conf_rclone)" --json "$PASTA_DRIVE/$nome" 2>>"$LOG" \
            | sed -n 's/.*"bytes":[[:space:]]*\([0-9]\{1,\}\).*/\1/p' | head -1)" || remoto=""
  if [[ "$remoto" != "$local_bytes" ]]; then
    falha "$nome: o tamanho no Drive (${remoto:-nada}) nao bate com o local ($local_bytes)"
    return 1
  fi

  CONFERENCIA="tamanho"
  md5r="$(rclone md5sum --config "$(arquivo_conf_rclone)" "$PASTA_DRIVE/$nome" 2>>"$LOG" \
          | awk 'NR==1{print $1}')" || md5r=""
  if [[ "$md5r" =~ ^[0-9a-fA-F]{32}$ ]]; then
    md5l="$(md5_local "$arquivo")"
    if [[ -n "$md5l" ]]; then
      if [[ "${md5r,,}" != "${md5l,,}" ]]; then
        falha "$nome: o conteudo no Drive nao confere (MD5 $md5r contra $md5l)"
        return 1
      fi
      CONFERENCIA="MD5"
      MD5_ENVIADO="${md5l,,}"
    fi
  fi

  BYTES_ENVIADOS=$((BYTES_ENVIADOS + local_bytes))
  return 0
}

retencao_drive() {
  ((POR_DATA)) || return 0
  ((DRIVE_MANTER > 0)) || return 0
  local base="${DRIVE_REMOTE}:${DRIVE_PASTA}"
  passo "Guardando as $DRIVE_MANTER pastas de data mais novas no Drive"
  local n=0 p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n=$((n + 1))
    ((n > DRIVE_MANTER)) || continue
    if rclone purge --config "$(arquivo_conf_rclone)" "$base/$p" >>"$LOG" 2>&1; then
      diz "removida do Drive: $p"
    else
      aviso "nao consegui remover do Drive: $p"
    fi
  done < <(rclone lsf --dirs-only --config "$(arquivo_conf_rclone)" "$base" 2>>"$LOG" \
           | sed 's#/$##' \
           | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' \
           | sort -r || true)
  return 0
}

# ---------------------------------------------------------------------------
# Cifra (opcional)
# ---------------------------------------------------------------------------
cifra_para_tmp() {  # cifra_para_tmp <origem> <nome base>  ->  imprime o caminho cifrado
  local arq="$1" base="$2" saida
  declare -a senha=()
  saida="$TMP/cifra/$base.gpg"
  mkdir -p "$(dirname "$saida")" || return 1
  if tem gpg; then
    [[ -n "$ARQUIVO_SENHA" ]] && senha=(--batch --yes --passphrase-file "$ARQUIVO_SENHA")
    gpg "${senha[@]+${senha[@]}}" --batch --yes --symmetric --cipher-algo AES256 \
        -o "$saida" "$arq" 2>>"$LOG" || return 1
    printf '%s' "$saida"
    return 0
  fi
  saida="$TMP/cifra/$base.enc"
  mkdir -p "$(dirname "$saida")" || return 1
  [[ -n "$ARQUIVO_SENHA" ]] && senha=(-pass "file:$ARQUIVO_SENHA")
  openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
    -in "$arq" -out "$saida" "${senha[@]+${senha[@]}}" 2>>"$LOG" || return 1
  printf '%s' "$saida"
  return 0
}

# ---------------------------------------------------------------------------
# Lista dos arquivos
# ---------------------------------------------------------------------------
# Padrao casa com o nome do arquivo ou com o caminho relativo inteiro. O $p vai
# sem aspas de proposito: e ele que faz o glob valer.
casa_padrao() {
  local rel="$1" nome="${1##*/}" p
  shift
  for p in "$@"; do
    # shellcheck disable=SC2053
    [[ "$nome" == $p ]] && return 0
    # shellcheck disable=SC2053
    [[ "$rel" == $p ]] && return 0
  done
  return 1
}

passa_filtros() {  # passa_filtros <relativo>  ->  0 entra, 1 fica de fora
  local rel="$1"
  if ((SEM_OCULTOS)) && [[ "/$rel" == */.* ]]; then
    FORA+=("$rel|oculto (--sem-ocultos)")
    return 1
  fi
  if ((${#INCLUIR[@]})) && ! casa_padrao "$rel" "${INCLUIR[@]}"; then
    FORA+=("$rel|nao casa com --incluir")
    return 1
  fi
  if ((${#EXCLUIR[@]})) && casa_padrao "$rel" "${EXCLUIR[@]}"; then
    FORA+=("$rel|casa com --excluir")
    return 1
  fi
  return 0
}

lista_arquivos() {
  local caminho rel tam limite=0
  declare -a flags=() prof=()
  ((SEGUIR_ATALHOS)) && flags+=(-L)
  ((SEM_SUBPASTAS)) && prof=(-maxdepth 1)
  ((MAX_MB > 0)) && limite=$((MAX_MB * 1024 * 1024))

  while IFS= read -r -d '' caminho; do
    rel="${caminho#"$ORIGEM"/}"
    [[ "$rel" != "$caminho" ]] || continue
    passa_filtros "$rel" || continue
    if [[ ! -r "$caminho" ]]; then
      FORA+=("$rel|sem permissao de leitura")
      continue
    fi
    tam="$(tamanho_arquivo "$caminho")"
    if ((limite > 0)) && ((tam > limite)); then
      FORA+=("$rel|maior que ${MAX_MB} MB ($(legivel "$tam"))")
      continue
    fi
    ARQUIVOS+=("$rel")
    TAMANHO_DE["$rel"]="$tam"
    BYTES_TOTAL=$((BYTES_TOTAL + tam))
  done < <(find ${flags[@]+"${flags[@]}"} "$ORIGEM" ${prof[@]+"${prof[@]}"} -type f -print0 2>/dev/null | ordena_z)

  # atalho simbolico fora do backup aparece no relatorio, para ninguem achar
  # que o conteudo apontado por ele subiu
  if ((SEGUIR_ATALHOS == 0)); then
    while IFS= read -r -d '' caminho; do
      rel="${caminho#"$ORIGEM"/}"
      [[ "$rel" != "$caminho" ]] || continue
      ATALHOS+=("$rel")
    done < <(find "$ORIGEM" ${prof[@]+"${prof[@]}"} -type l -print0 2>/dev/null | ordena_z)
  fi

  # pasta vazia nao existe no Google Drive: ele nao guarda pasta sem arquivo
  if ((SEM_SUBPASTAS)); then return 0; fi
  while IFS= read -r -d '' caminho; do
    [[ "$caminho" != "$ORIGEM" ]] || continue
    rel="${caminho#"$ORIGEM"/}"
    [[ "$rel" != "$caminho" ]] || continue
    VAZIAS+=("$rel")
  done < <(find "$ORIGEM" -mindepth 1 -type d -empty -print0 2>/dev/null | ordena_z)
  return 0
}

# ---------------------------------------------------------------------------
# Registro dos arquivos ja enviados, e retomada
#
# Backup de 900 arquivos que morre no 300 nao pode recomecar do zero. Todo
# arquivo que sobe deixa uma linha aqui, e a execucao seguinte le isso para
# saber de onde continuar.
#
# O registro sozinho nao decide nada: ele diz onde o arquivo deveria estar, e o
# script vai CONFERIR no Drive que ele esta mesmo la antes de pular. Registro
# que aponta para arquivo que sumiu vira aviso, e o arquivo sobe de novo.
#
# Uma linha por arquivo enviado, separada por tabulacao:
#   epoch  data_legivel  relativo  situacao  bytes  mtime  md5  destino
# ---------------------------------------------------------------------------
registra() {  # registra <relativo> <situacao> <bytes> <mtime> <md5> <destino>
  [[ -n "$REGISTRO" ]] || return 0
  { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date +%s)" "$(date '+%d/%m/%Y %H:%M')" "$1" "$2" "${3:-0}" "${4:-0}" "${5:--}" "${6:--}" \
      >> "$REGISTRO"; } 2>/dev/null || true
  chmod 600 "$REGISTRO" 2>/dev/null || true
  return 0
}

EXISTE_QUANDO=""; EXISTE_BYTES=0; EXISTE_MTIME=0; EXISTE_ONDE=""

# 0 = ja esta no Drive e nao mudou aqui, pode pular. 1 = tem que enviar.
ja_enviado() {
  local rel="$1" linha epoch quando bytes mtime destino remoto
  EXISTE_QUANDO=""; EXISTE_BYTES=0; EXISTE_MTIME=0; EXISTE_ONDE=""

  ((REFAZER)) && return 1
  [[ -f "$REGISTRO" ]] || return 1
  linha="$(awk -F'\t' -v r="$rel" '$3==r && $4=="ok" {l=$0} END{print l}' "$REGISTRO" 2>/dev/null)" || linha=""
  [[ -n "$linha" ]] || return 1

  IFS=$'\t' read -r epoch quando _rel _situacao bytes mtime _md5 destino <<< "$linha"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  EXISTE_QUANDO="$quando"; EXISTE_BYTES="${bytes:-0}"; EXISTE_MTIME="${mtime:-0}"; EXISTE_ONDE="$destino"

  # mudou aqui? entao tem que subir de novo, por mais recente que seja o registro
  if [[ "${TAMANHO_DE[$rel]}" != "$EXISTE_BYTES" ]]; then return 1; fi
  if [[ "$(mtime_de "$ORIGEM/$rel")" != "$EXISTE_MTIME" ]]; then return 1; fi

  # A mesma pasta de origem pode ter sido enviada para duas pastas diferentes do
  # Drive, e as duas vezes caem neste mesmo registro. Linha que aponta para
  # OUTRO destino nao vale aqui: valer faria o arquivo ser pulado sem nunca
  # chegar na pasta desta execucao.
  [[ "$destino" == "$PASTA_DRIVE/"* ]] || return 1

  # e a parte que importa: conferir que o arquivo esta mesmo la
  [[ "$destino" == *:* ]] || return 1
  remoto="$(rclone size --config "$(arquivo_conf_rclone)" --json "$destino" 2>>"$LOG" \
            | sed -n 's/.*"bytes":[[:space:]]*\([0-9]\{1,\}\).*/\1/p' | head -1)" || remoto=""
  if [[ -z "$remoto" || "$remoto" != "$EXISTE_BYTES" ]]; then
    aviso "$rel: o registro apontava para $destino, mas o arquivo nao esta la do mesmo jeito. Vou enviar de novo."
    return 1
  fi
  return 0
}

mostra_registro() {
  if [[ ! -s "$REGISTRO" ]]; then
    printf '\n  Nenhum arquivo registrado ainda em %s\n\n' "$REGISTRO"
    return 0
  fi
  printf '\n  %-48s %-18s %10s %-10s\n' ARQUIVO QUANDO TAMANHO SITUACAO
  printf '  %s\n' "$(printf '%.0s-' {1..92})"
  local epoch quando rel situacao bytes mtime md5 destino
  while IFS=$'\t' read -r epoch quando rel situacao bytes mtime md5 destino; do
    [[ -n "$rel" ]] || continue
    printf '  %-48s %-18s %10s %-10s\n' \
      "$(printf '%s' "$rel" | cut -c1-48)" "$quando" "$(legivel "${bytes:-0}")" "$situacao"
  done < "$REGISTRO"
  printf '\n  O registro fica em %s\n\n' "$REGISTRO"
  return 0
}

# ---------------------------------------------------------------------------
# Modo --conectar: so liga o Drive e sai
# ---------------------------------------------------------------------------
if ((SO_CONECTAR)); then
  TMP="$(mktemp -d)"; chmod 700 "$TMP"
  trap na_saida EXIT
  trap 'morre "interrompido pelo operador"' INT TERM
  LOG="$TMP/conectar.log"; : > "$LOG"
  if configura_drive; then
    printf '\n%s\n' "$(cor '1;32' 'Google Drive conectado.')"
    printf '  Agora rode o backup apontando a pasta:\n\n'
    printf '    ./%s /caminho/da/pasta\n\n' "$NOME_SCRIPT"
    printf '  Ele pergunta o nome da pasta que vai criar no seu Drive.\n\n'
    exit 0
  fi
  morre "a autorizacao do Google Drive nao terminou"
fi

# ---------------------------------------------------------------------------
# Conferindo o terreno
# ---------------------------------------------------------------------------
passo "Conferindo o terreno"

for prog in find awk sed sort date stat mktemp tr cut; do
  tem "$prog" || morre "falta o comando '$prog' nesta maquina"
done
if ! tem md5sum && ! tem md5; then
  aviso "sem md5sum nesta maquina: a conferencia no Drive vai ser por tamanho, nao por conteudo"
fi

if [[ -z "$ORIGEM" ]]; then
  if tem_terminal && ((SO_REGISTRO == 0)); then
    ORIGEM="$(le_do_tty 'Qual pasta voce quer enviar para o Drive')"
  fi
  [[ -n "$ORIGEM" ]] || morre "diga qual pasta enviar: ./$NOME_SCRIPT /caminho/da/pasta"
fi
# ~ digitado a mao nao e expandido pelo read
case "$ORIGEM" in "~/"*) ORIGEM="$HOME/${ORIGEM#\~/}" ;; "~") ORIGEM="$HOME" ;; esac
[[ -e "$ORIGEM" ]] || morre "nao achei essa pasta: $ORIGEM"
[[ -d "$ORIGEM" ]] || morre "isso nao e uma pasta: $ORIGEM"
[[ -r "$ORIGEM" ]] || morre "sem permissao de leitura em: $ORIGEM"
ORIGEM="$(cd "$ORIGEM" && pwd -P)"
[[ "$ORIGEM" != "/" ]] || morre "a raiz do sistema nao e pasta de backup. Aponte uma pasta de verdade."
feito "origem: $ORIGEM"

if ((SEM_NICE == 0)); then
  renice -n 19 -p $$ >/dev/null 2>&1 || true
  tem ionice && ionice -c 3 -p $$ >/dev/null 2>&1 || true
  feito "prioridade baixa de CPU e disco, para nao travar a maquina"
fi

if [[ -n "$ARQUIVO_SENHA" && ! -r "$ARQUIVO_SENHA" ]]; then
  morre "nao consigo ler o arquivo de senha: $ARQUIVO_SENHA"
fi
if ((CIFRAR)) && ! tem gpg && ! tem openssl; then
  morre "--cifrar precisa de gpg ou openssl instalado"
fi
if ((CIFRAR)) && [[ -z "$ARQUIVO_SENHA" ]] && ! tem_terminal; then
  morre "--cifrar sem --senha-arquivo precisa de terminal para pedir a senha"
fi

# ---------------------------------------------------------------------------
# Nome da pasta no Drive, e a pasta de estado
# ---------------------------------------------------------------------------
if [[ -n "$DRIVE_PASTA" ]]; then
  DRIVE_PASTA="${DRIVE_PASTA#/}"; DRIVE_PASTA="${DRIVE_PASTA%/}"
  motivo_nome=""
  if ! motivo_nome="$(valida_nome_drive "$DRIVE_PASTA")"; then
    morre "--drive-pasta: $motivo_nome"
  fi
elif ((SIMULAR)) || ((SO_REGISTRO)); then
  # nem a simulacao nem o --registro criam pasta no Drive, entao aqui o nome e
  # so ilustrativo: quem escolhe de verdade e a execucao que envia
  DRIVE_PASTA="$(basename "$ORIGEM")"
else
  pede_nome_da_pasta
fi
feito "pasta no Drive: $DRIVE_PASTA"

if [[ -n "$ESTADO_PEDIDO" ]]; then
  ESTADO="$ESTADO_PEDIDO"
else
  # a chave e a ORIGEM, nao a pasta do Drive: assim --registro funciona dando
  # so o caminho, sem a pessoa ter que lembrar o nome que digitou no Drive
  ESTADO="${HOME:-/tmp}/.backup-avulso/$(apelido "$(basename "$ORIGEM")")-$(id_da_origem "$ORIGEM")"
fi
mkdir -p "$ESTADO" || morre "nao consegui criar a pasta de estado: $ESTADO"
ESTADO="$(cd "$ESTADO" && pwd -P)"
chmod 700 "$ESTADO" 2>/dev/null || true
# estado dentro da origem faria o backup copiar o proprio registro, e crescer a
# cada execucao
if [[ "$ESTADO" == "$ORIGEM" || "$ESTADO" == "$ORIGEM"/* ]]; then
  morre "a pasta de estado nao pode ficar dentro da origem ($ESTADO). Use --estado OUTRO_LUGAR."
fi
REGISTRO="$ESTADO/registro.tsv"
feito "estado: $ESTADO"

if ((SO_REGISTRO)); then
  mostra_registro
  exit 0
fi

TMP="$(mktemp -d)"; chmod 700 "$TMP"

if ((SIMULAR)); then
  # simulacao nao deixa rastro e nao toma a trava: ela e leitura, e tem que
  # poder rodar com um backup de verdade em andamento
  LOG="$TMP/simulacao.log"; : > "$LOG"
else
  LOG="$ESTADO/backup-$CARIMBO.log"
  : > "$LOG"; chmod 600 "$LOG"

  TRAVA="$ESTADO/backup-avulso.lock"
  if tem flock; then
    exec 9>"$TRAVA"
    flock -n 9 || morre "ja existe um backup desta pasta em andamento (trava: $TRAVA)"
  fi
fi

trap na_saida EXIT
trap 'morre "interrompido pelo operador"' INT TERM

# ---------------------------------------------------------------------------
# Lista
# ---------------------------------------------------------------------------
passo "Listando os arquivos de $ORIGEM"

lista_arquivos

if ((${#ARQUIVOS[@]} == 0)); then
  if ((${#FORA[@]})); then
    printf '\n  Arquivos que vi e deixei de fora:\n'
    for linha in "${FORA[@]}"; do
      printf '    %-56s %s\n' "$(printf '%s' "${linha%%|*}" | cut -c1-56)" "${linha#*|}"
    done
  fi
  morre "nenhum arquivo para enviar em $ORIGEM"
fi

feito "${#ARQUIVOS[@]} arquivo(s), $(legivel "$BYTES_TOTAL") no total"
((${#FORA[@]}))    && diz "${#FORA[@]} arquivo(s) de fora pelos filtros"
((${#ATALHOS[@]})) && diz "${#ATALHOS[@]} atalho(s) simbolico(s) de fora (use --seguir-atalhos para incluir)"
((${#VAZIAS[@]}))  && diz "${#VAZIAS[@]} pasta(s) vazia(s): o Google Drive nao guarda pasta sem arquivo"

# ---------------------------------------------------------------------------
# Simulacao
# ---------------------------------------------------------------------------
if ((SIMULAR)); then
  passo "Simulando (nada vai ser criado no Drive nem enviado)"
  printf '\n  %-62s %10s\n' ARQUIVO TAMANHO
  printf '  %s\n' "$(printf '%.0s-' {1..75})"
  for rel in "${ARQUIVOS[@]}"; do
    printf '  %-62s %10s\n' "$(printf '%s' "$rel" | cut -c1-62)" "$(legivel "${TAMANHO_DE[$rel]}")"
  done
  printf '  %s\n' "$(printf '%.0s-' {1..75})"
  printf '  %-62s %10s\n\n' "${#ARQUIVOS[@]} arquivo(s)" "$(legivel "$BYTES_TOTAL")"
  if ((${#FORA[@]})); then
    printf '  De fora pelos filtros (%s):\n' "${#FORA[@]}"
    for linha in "${FORA[@]}"; do
      printf '    %-56s %s\n' "$(printf '%s' "${linha%%|*}" | cut -c1-56)" "${linha#*|}"
    done
    printf '\n'
  fi
  printf '  Pasta que seria criada no Drive: %s:%s%s\n' "$DRIVE_REMOTE" "$DRIVE_PASTA" \
    "$( ((POR_DATA)) && printf '/%s' "$PASTA_DATA" )"
  printf '  O nome da pasta e perguntado na execucao de verdade, nao aqui.\n'
  printf '  Nada na pasta de origem e tocado: o script so le.\n\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Drive antes de gastar tempo
# ---------------------------------------------------------------------------
if ! instala_rclone; then
  morre "sem rclone nao da para enviar ao Google Drive"
fi
if ! remote_ja_existe || ! testa_remote; then
  configura_drive || morre "o Google Drive nao esta conectado. Rode: ./$NOME_SCRIPT --conectar"
else
  feito "Google Drive respondendo no remote '$DRIVE_REMOTE'"
fi

passo "Criando a pasta no Google Drive"
cria_pasta_drive || morre "sem pasta no Drive nao da para enviar"

PASTA_DRIVE="${DRIVE_REMOTE}:${DRIVE_PASTA}"
if ((POR_DATA)); then
  PASTA_DRIVE="$PASTA_DRIVE/$PASTA_DATA"
  rclone mkdir --config "$(arquivo_conf_rclone)" --log-level ERROR --log-file "$LOG" "$PASTA_DRIVE" 2>>"$LOG" \
    || aviso "nao consegui criar a subpasta de data; o envio cria sozinho no caminho"
fi
feito "destino no Drive: $PASTA_DRIVE"

# senha da cifra uma vez, para nao perguntar arquivo por arquivo
if ((CIFRAR)) && [[ -z "$ARQUIVO_SENHA" ]]; then
  senha1="$(le_do_tty 'Senha da cifra' oculto)"
  senha2="$(le_do_tty 'Repita a senha' oculto)"
  [[ -n "$senha1" ]] || morre "senha vazia"
  [[ "$senha1" == "$senha2" ]] || morre "as duas senhas nao sao iguais"
  ARQUIVO_SENHA="$TMP/senha"
  ( umask 077; printf '%s' "$senha1" > "$ARQUIVO_SENHA" )
  unset senha1 senha2
  feito "senha da cifra guardada so pelo tempo desta execucao"
  aviso "arquivo cifrado so volta com essa senha. Perdeu a senha, perdeu o backup."
fi

# ---------------------------------------------------------------------------
# A pergunta, uma vez
# ---------------------------------------------------------------------------
printf '\n'
printf '  Vou enviar %s arquivo(s), %s, de\n' "${#ARQUIVOS[@]}" "$(legivel "$BYTES_TOTAL")"
printf '    %s\n' "$ORIGEM"
printf '  para\n'
printf '    %s\n' "$PASTA_DRIVE"
printf '  Nada na pasta de origem e apagado nem alterado.\n\n'
if ! pergunta_sim "Pode enviar?"; then
  morre "nada foi enviado"
fi

# ---------------------------------------------------------------------------
# Um arquivo por vez
# ---------------------------------------------------------------------------
TOTAL=${#ARQUIVOS[@]}
N=0

for rel in "${ARQUIVOS[@]}"; do
  N=$((N + 1))
  caminho="$ORIGEM/$rel"
  tam="${TAMANHO_DE[$rel]}"
  comeco="$(date +%s)"
  rotulo="$(printf '[%s/%s]' "$N" "$TOTAL")"

  if ja_enviado "$rel"; then
    printf '%s %s %s %s\n' "$(cor '0;90' "$rotulo")" "$(cor '0;32' 'ja esta')" \
      "$rel" "$(cor '0;90' "($EXISTE_QUANDO)")"
    PULADOS=$((PULADOS + 1))
    LINHAS_RELATORIO+=("$rel	$tam	ja-estava	0")
    continue
  fi

  printf '%s %s  %s\n' "$(cor '0;90' "$rotulo")" "$rel" "$(cor '0;90' "$(legivel "$tam")")"

  enviar="$caminho"
  nome_destino="$rel"
  if ((CIFRAR)); then
    if cifrado="$(cifra_para_tmp "$caminho" "$rel")"; then
      enviar="$cifrado"
      nome_destino="$rel.${cifrado##*.}"
    else
      falha "$rel: a cifra falhou (veja $LOG)"
      FALHA_ARQ=$((FALHA_ARQ + 1))
      LINHAS_RELATORIO+=("$rel	$tam	erro-cifra	0")
      registra "$rel" falha "$tam" "$(mtime_de "$caminho")" "-" "-"
      continue
    fi
  fi

  if envia_arquivo "$enviar" "$nome_destino"; then
    OK_ARQ=$((OK_ARQ + 1))
    [[ "$CONFERENCIA" == "MD5" ]] || CONFERENCIA_POR_TAMANHO=1
    gasto=$(( $(date +%s) - comeco ))
    LINHAS_RELATORIO+=("$rel	$tam	ok-$CONFERENCIA	$gasto")
    registra "$rel" ok "$tam" "$(mtime_de "$caminho")" "${MD5_ENVIADO:--}" "$PASTA_DRIVE/$nome_destino"
  else
    FALHA_ARQ=$((FALHA_ARQ + 1))
    gasto=$(( $(date +%s) - comeco ))
    LINHAS_RELATORIO+=("$rel	$tam	erro-envio	$gasto")
    registra "$rel" falha "$tam" "$(mtime_de "$caminho")" "-" "$PASTA_DRIVE/$nome_destino"
  fi
  ((CIFRAR)) && rm -f "$enviar"
done

# ---------------------------------------------------------------------------
# Relatorio
# ---------------------------------------------------------------------------
passo "Escrevendo o relatorio"

DURACAO=$(( $(date +%s) - INICIO_EPOCH ))
RELATORIO="$ESTADO/RELATORIO-$CARIMBO.txt"

{
  echo "BACKUP DE PASTA PARA O GOOGLE DRIVE"
  echo
  echo "MAQUINA ........ $(hostname 2>/dev/null || echo desconhecida)"
  echo "DATA ........... $(date '+%d/%m/%Y %H:%M:%S')"
  echo "SCRIPT ......... $NOME_SCRIPT v$VERSAO_SCRIPT"
  echo "ORIGEM ......... $ORIGEM"
  echo "DESTINO DRIVE .. $PASTA_DRIVE"
  echo "ESTADO ......... $ESTADO"
  echo "SUBPASTAS ...... $( ((SEM_SUBPASTAS)) && echo 'nao, so a raiz da pasta' || echo 'sim, estrutura repetida no Drive' )"
  echo "ATALHOS ........ $( ((SEGUIR_ATALHOS)) && echo 'conteudo apontado foi enviado' || echo 'ficaram de fora' )"
  echo "CIFRA .......... $( ((CIFRAR)) && echo AES256 || echo nao )"
  if ((CONFERENCIA_POR_TAMANHO)); then
    echo "CONFERENCIA .... tamanho no Drive em pelo menos um arquivo (o Drive nao devolveu hash)"
  else
    echo "CONFERENCIA .... MD5 do conteudo lido no proprio Drive"
  fi
  echo "DURACAO ........ $((DURACAO / 60))m $((DURACAO % 60))s"
  echo
  printf '%-62s %12s %-12s %8s\n' ARQUIVO TAMANHO SITUACAO TEMPO
  printf '%s\n' "$(printf '%.0s-' {1..98})"
  for linha in ${LINHAS_RELATORIO[@]+"${LINHAS_RELATORIO[@]}"}; do
    IFS=$'\t' read -r a t si te <<< "$linha"
    printf '%-62s %12s %-12s %7ss\n' "$a" "$(legivel "$t")" "$si" "$te"
  done
  echo
  echo "ENVIADOS ....... $OK_ARQ"
  echo "COM ERRO ....... $FALHA_ARQ"
  echo "JA ESTAVAM ..... $PULADOS"
  echo "BYTES ENVIADOS . $(legivel "$BYTES_ENVIADOS")"
  echo
  if ((${#FORA[@]})); then
    echo "DE FORA PELOS FILTROS (${#FORA[@]})"
    for linha in "${FORA[@]}"; do printf '  %-62s %s\n' "${linha%%|*}" "${linha#*|}"; done
    echo
  fi
  if ((${#ATALHOS[@]})); then
    echo "ATALHOS SIMBOLICOS NAO ENVIADOS (${#ATALHOS[@]})"
    for a in "${ATALHOS[@]}"; do printf '  %s\n' "$a"; done
    echo
  fi
  if ((${#VAZIAS[@]})); then
    echo "PASTAS VAZIAS, QUE NAO EXISTEM NO DRIVE (${#VAZIAS[@]})"
    for a in "${VAZIAS[@]}"; do printf '  %s\n' "$a"; done
    echo
  fi
  echo "AVISOS (${#AVISOS[@]})"
  for a in ${AVISOS[@]+"${AVISOS[@]}"}; do echo "  - $a"; done
  echo
  echo "FALHAS (${#ERROS[@]})"
  for e in ${ERROS[@]+"${ERROS[@]}"}; do echo "  - $e"; done
  echo
  echo "COMO TRAZER OS ARQUIVOS DE VOLTA"
  echo "  Pelo site do Google Drive, baixando a pasta, ou pelo rclone:"
  echo "    rclone copy $PASTA_DRIVE /caminho/onde/restaurar -P"
  if ((CIFRAR)); then
    echo "  Cada arquivo esta cifrado. Para abrir um:"
    echo "    gpg --output arquivo --decrypt arquivo.gpg"
    echo "  Sem a senha nao existe como abrir."
  fi
  echo
  echo "ESTE RELATORIO LISTA OS NOMES DOS SEUS ARQUIVOS. Trate como informacao"
  echo "sua, nao publique."
} > "$RELATORIO"
chmod 600 "$RELATORIO"
feito "$(basename "$RELATORIO")"

pasta_rel="${DRIVE_REMOTE}:${DRIVE_PASTA}/_relatorios"
if rclone copyto --config "$(arquivo_conf_rclone)" --log-level ERROR --log-file "$LOG" \
     "$RELATORIO" "$pasta_rel/$(basename "$RELATORIO")" 2>>"$LOG"; then
  feito "relatorio enviado para $pasta_rel"
else
  aviso "o relatorio nao foi enviado ao Drive, mas esta em $RELATORIO"
fi

retencao_drive

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
printf '\n%s\n' "$(cor '1;32' '=========================== BACKUP CONCLUIDO ===========================')"
printf '  Enviados ...... %s de %s\n' "$OK_ARQ" "$TOTAL"
printf '  Ja estavam .... %s\n' "$PULADOS"
printf '  Com erro ...... %s\n' "$FALHA_ARQ"
printf '  No Drive ...... %s\n' "$PASTA_DRIVE"
printf '  Enviado ....... %s\n' "$(legivel "$BYTES_ENVIADOS")"
printf '  Relatorio ..... %s\n' "$RELATORIO"
printf '  Duracao ....... %dm %ds\n' $((DURACAO / 60)) $((DURACAO % 60))
printf '  Avisos ........ %s\n' "${#AVISOS[@]}"
printf '  Falhas ........ %s\n' "${#ERROS[@]}"

if ((${#ERROS[@]})); then
  printf '\n%s\n' "$(cor '1;31' 'FALHAS QUE PRECISAM DE OLHO:')"
  for e in "${ERROS[@]}"; do printf '  - %s\n' "$e"; done
  printf '\n  Rode o mesmo comando de novo: o que ja subiu e pulado, e ele tenta\n'
  printf '  so o que faltou.\n'
fi
if ((${#AVISOS[@]})); then
  printf '\n%s\n' "$(cor '1;33' 'AVISOS:')"
  for a in "${AVISOS[@]}"; do printf '  - %s\n' "$a"; done
fi

printf '\n  Sua pasta de origem continua intacta: o script so leu dela.\n\n'

if ((FALHA_ARQ > 0 || ${#ERROS[@]} > 0)); then exit 2; fi
exit 0
