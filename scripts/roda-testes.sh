#!/usr/bin/env bash
# Bateria de testes do backup-avulso.sh contra o Google Drive de mentira.
# Antes: bash scripts/monta-lab.sh
set -uo pipefail

SC="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$SC/.." && pwd -P)"
LAB="$REPO/.lab"
ORIGEM="$LAB/origem"
DRIVE="$LAB/drive"
CASA="$LAB/casa"
S="$REPO/backup-avulso.sh"

[[ -d "$LAB" ]] || { echo "monte o lab primeiro: bash scripts/monta-lab.sh" >&2; exit 1; }

export PATH="$LAB/bin:$PATH"
export HOME="$CASA"

PASSOU=0; REPROVOU=0
declare -a FALHAS=()

ok()   { PASSOU=$((PASSOU+1));     printf '  \033[0;32mPASS\033[0m  %s\n' "$1"; }
nok()  { REPROVOU=$((REPROVOU+1)); FALHAS+=("$1"); printf '  \033[1;31mFAIL\033[0m  %s\n' "$1"; }
caso() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }

N_RODADA=0
roda() {
  N_RODADA=$((N_RODADA + 1))
  SAIDA="$( cd "$LAB" && bash "$S" "$@" 2>&1 )"
  CODIGO=$?
  ULTIMA="$LAB/saida-$N_RODADA.txt"
  { printf 'argumentos: %s\ncodigo: %s\n\n' "$*" "$CODIGO"; printf '%s\n' "$SAIDA"; } > "$ULTIMA"
  if ((CODIGO != 0)); then
    printf '        [rodada %s, codigo %s] %s\n' "$N_RODADA" "$CODIGO" "$*"
    grep -E '^[[:space:]]+(xx|!!)|^ERRO:' <<< "$SAIDA" | sed 's/^/          /' | head -8
    printf '          saida completa: %s\n' "$ULTIMA"
  fi
  return 0
}

limpa() {
  rm -rf "$DRIVE" "$CASA" "$LAB/rclone.conf" "$LAB/.corromper" "$LAB/.hash-errado"
  mkdir -p "$DRIVE" "$CASA"
}
conecta()    { touch "$LAB/.conectado"; }
desconecta() { rm -f "$LAB/.conectado"; }

contem()     { grep -qF -- "$2" <<< "$1"; }
nao_contem() { ! grep -qF -- "$2" <<< "$1"; }

# assinatura da arvore de origem, para provar que o script nao mexeu nela
assina_origem() {
  ( cd "$ORIGEM" && find . \( -type f -o -type l \) -print | LC_ALL=C sort \
    && find . -type f -exec md5sum {} + 2>/dev/null | LC_ALL=C sort ) | md5sum
}

pasta_estado() {
  local d
  d="$(ls -d "$CASA/.backup-avulso/"*/ 2>/dev/null | head -1)" || d=""
  printf '%s' "${d%/}"
}

# nesta maquina o atalho simbolico pode nao existir (ver monta-lab.sh)
TEM_ATALHO=1
[[ -f "$LAB/.sem-atalhos" ]] && TEM_ATALHO=0
pula() { printf '        pulado: %s
' "$1"; }

ASSINATURA_INICIAL="$(assina_origem)"

# ===========================================================================
caso "T01 lista os arquivos da pasta"
limpa; desconecta
roda "$ORIGEM" --simular
contem "$SAIDA" "13 arquivo(s)"                  && ok "acha os 13 arquivos da arvore" || nok "T01 contagem"
contem "$SAIDA" "documentos/contrato.pdf"        && ok "entra na subpasta" || nok "T01 subpasta"
contem "$SAIDA" "sub/mais/fundo/perdido.txt"     && ok "entra na subpasta de subpasta" || nok "T01 fundo"
contem "$SAIDA" "pasta com espaco/arquivo com acento cao.txt" && ok "nome com espaco e acento aparece" || nok "T01 espaco"
if ((TEM_ATALHO)); then
  contem "$SAIDA" "1 atalho(s) simbolico(s) de fora" && ok "atalho simbolico fica de fora e e avisado" || nok "T01 atalho"
else
  pula "atalho simbolico nao existe nesta maquina"
fi
contem "$SAIDA" "1 pasta(s) vazia(s)"            && ok "avisa que pasta vazia nao existe no Drive" || nok "T01 vazia"
contem "$SAIDA" "so le"                          && ok "diz que a origem nao e tocada" || nok "T01 so le"
((CODIGO == 0))                                  && ok "--simular sai com 0" || nok "T01 codigo=$CODIGO"
[[ -z "$(ls -A "$DRIVE" 2>/dev/null)" ]]         && ok "--simular nao criou nada no Drive" || nok "T01 simular criou no Drive"

# ===========================================================================
caso "T02 filtros"
roda "$ORIGEM" --simular --sem-ocultos
contem "$SAIDA" "12 arquivo(s)" && ok "--sem-ocultos tira o arquivo com ponto" || nok "T02 sem-ocultos"
grep -qE '^\s+\.configuracao\s+oculto \(--sem-ocultos\)$' <<< "$SAIDA"   && ok "o oculto aparece na lista do que ficou de fora, com o motivo" || nok "T02 motivo do oculto"

roda "$ORIGEM" --simular --sem-subpastas
contem "$SAIDA" "3 arquivo(s)" && ok "--sem-subpastas pega so a raiz" || nok "T02 sem-subpastas"
nao_contem "$SAIDA" "contrato.pdf" && ok "--sem-subpastas nao desce" || nok "T02 desceu"

roda "$ORIGEM" --simular --incluir '*.jpg'
contem "$SAIDA" "2 arquivo(s)" && ok "--incluir pega so o padrao" || nok "T02 incluir"

roda "$ORIGEM" --simular --excluir '*.tmp'
contem "$SAIDA" "12 arquivo(s)" && ok "--excluir tira o padrao" || nok "T02 excluir"

roda "$ORIGEM" --simular --excluir 'node_modules/*'
contem "$SAIDA" "12 arquivo(s)" && ok "--excluir aceita padrao de caminho" || nok "T02 excluir caminho"

roda "$ORIGEM" --simular --max-mb 1
contem "$SAIDA" "12 arquivo(s)"             && ok "--max-mb tira o arquivo grande" || nok "T02 max-mb"
contem "$SAIDA" "maior que 1 MB"            && ok "diz por que ficou de fora" || nok "T02 max-mb motivo"

if ((TEM_ATALHO)); then
  roda "$ORIGEM" --simular --seguir-atalhos
  contem "$SAIDA" "14 arquivo(s)" && ok "--seguir-atalhos traz o conteudo do atalho" || nok "T02 seguir-atalhos"
else
  pula "--seguir-atalhos: sem atalho nesta maquina"
fi

# ===========================================================================
caso "T03 cria no Drive a pasta com o nome escolhido"
limpa; conecta
roda "$ORIGEM" --drive-pasta MeuBackup -s
((CODIGO == 0)) && ok "sai com 0" || nok "T03 codigo=$CODIGO"
[[ -d "$DRIVE/MeuBackup" ]] && ok "a pasta MeuBackup existe no Drive" || nok "T03 pasta nao criada"
contem "$SAIDA" "pasta 'MeuBackup' criada no Google Drive" && ok "diz que criou a pasta" || nok "T03 aviso de criacao"
contem "$SAIDA" "Enviados ...... 13 de 13" && ok "enviou os 13" || nok "T03 enviados"

# ===========================================================================
caso "T04 cada arquivo chega no Drive, igual, no mesmo caminho"
IGUAIS=0; DIFERENTES=0
while IFS= read -r rel; do
  o="$ORIGEM/$rel"; d="$DRIVE/MeuBackup/$rel"
  if [[ -f "$d" ]] && cmp -s "$o" "$d"; then IGUAIS=$((IGUAIS+1)); else DIFERENTES=$((DIFERENTES+1)); printf '        diferente: %s\n' "$rel"; fi
done < <( cd "$ORIGEM" && find . -type f -printf '%P\n' 2>/dev/null || ( cd "$ORIGEM" && find . -type f | sed 's#^\./##' ) )
((IGUAIS == 13 && DIFERENTES == 0)) && ok "os 13 arquivos chegaram byte a byte iguais" || nok "T04 iguais=$IGUAIS diferentes=$DIFERENTES"
[[ -f "$DRIVE/MeuBackup/pasta com espaco/arquivo com acento cao.txt" ]] && ok "nome com espaco e acento chegou certo" || nok "T04 nome com espaco"
[[ -f "$DRIVE/MeuBackup/documentos/com'aspas\"duplas.txt" ]] && ok "nome com aspas chegou certo" || nok "T04 aspas"
[[ -f "$DRIVE/MeuBackup/documentos/\$cifrao e crase\`.txt" ]] && ok "nome com cifrao e crase chegou certo" || nok "T04 cifrao"
[[ ! -e "$DRIVE/MeuBackup/vazia" ]] && ok "pasta vazia nao foi criada no Drive" || nok "T04 pasta vazia criada"
if ((TEM_ATALHO)); then
  [[ ! -e "$DRIVE/MeuBackup/documentos/atalho.txt" ]] && ok "atalho simbolico nao subiu" || nok "T04 atalho subiu"
else
  pula "atalho simbolico nao existe nesta maquina"
fi

# ===========================================================================
caso "T05 relatorio"
EST="$(pasta_estado)"
[[ -n "$EST" ]] && ok "criou a pasta de estado em $HOME/.backup-avulso" || nok "T05 sem pasta de estado"
ls "$EST"/RELATORIO-*.txt >/dev/null 2>&1 && ok "escreveu o relatorio" || nok "T05 sem relatorio"
REL="$(cat "$EST"/RELATORIO-*.txt 2>/dev/null)"
contem "$REL" "ENVIADOS ....... 13"   && ok "relatorio diz 13 enviados" || nok "T05 relatorio enviados"
contem "$REL" "CONFERENCIA .... MD5"  && ok "relatorio diz que conferiu por MD5" || nok "T05 relatorio conferencia"
contem "$REL" "PASTAS VAZIAS"         && ok "relatorio lista a pasta vazia" || nok "T05 relatorio vazias"
if ((TEM_ATALHO)); then
  contem "$REL" "ATALHOS SIMBOLICOS"  && ok "relatorio lista o atalho de fora" || nok "T05 relatorio atalhos"
else
  pula "relatorio de atalhos: sem atalho nesta maquina"
fi
ls "$DRIVE/MeuBackup/_relatorios"/RELATORIO-*.txt >/dev/null 2>&1 && ok "relatorio subiu para _relatorios" || nok "T05 relatorio no Drive"
[[ -z "$(ls -A "$ORIGEM" | grep -i relatorio)" ]] && ok "o relatorio nao foi escrito dentro da origem" || nok "T05 relatorio na origem"

# ===========================================================================
caso "T06 a origem nao foi tocada"
[[ "$(assina_origem)" == "$ASSINATURA_INICIAL" ]] && ok "a arvore de origem esta identica a antes do backup" || nok "T06 a origem mudou"

# ===========================================================================
caso "T07 segunda execucao: pula o que nao mudou"
roda "$ORIGEM" --drive-pasta MeuBackup -s
contem "$SAIDA" "Ja estavam .... 13" && ok "pula os 13 que nao mudaram" || nok "T07 nao pulou"
contem "$SAIDA" "Enviados ...... 0 de 13" && ok "nao reenviou nada" || nok "T07 reenviou"

# ===========================================================================
caso "T08 arquivo que mudou sobe de novo, arquivo novo sobe"
printf 'contrato revisado, outro tamanho\n' > "$ORIGEM/documentos/contrato.pdf"
printf 'arquivo que nasceu agora\n' > "$ORIGEM/documentos/novo.txt"
roda "$ORIGEM" --drive-pasta MeuBackup -s
contem "$SAIDA" "Enviados ...... 2 de 14"  && ok "sobe so o que mudou e o que e novo" || nok "T08 enviados"
contem "$SAIDA" "Ja estavam .... 12"       && ok "os outros 12 continuam pulados" || nok "T08 pulados"
cmp -s "$ORIGEM/documentos/contrato.pdf" "$DRIVE/MeuBackup/documentos/contrato.pdf" \
  && ok "a versao nova do arquivo substituiu a antiga no Drive" || nok "T08 conteudo velho no Drive"
[[ -f "$DRIVE/MeuBackup/documentos/novo.txt" ]] && ok "o arquivo novo chegou" || nok "T08 novo nao chegou"

# ===========================================================================
caso "T09 arquivo apagado do Drive a mao volta a subir"
rm -f "$DRIVE/MeuBackup/leia-me.txt"
roda "$ORIGEM" --drive-pasta MeuBackup -s
contem "$SAIDA" "nao esta la do mesmo jeito" && ok "percebe que o arquivo sumiu do Drive" || nok "T09 nao percebeu"
[[ -f "$DRIVE/MeuBackup/leia-me.txt" ]] && ok "enviou de novo" || nok "T09 nao reenviou"

# ===========================================================================
caso "T10 --refazer envia tudo outra vez"
roda "$ORIGEM" --drive-pasta MeuBackup -s --refazer
contem "$SAIDA" "Enviados ...... 14 de 14" && ok "--refazer reenvia todos" || nok "T10 refazer"
contem "$SAIDA" "Ja estavam .... 0"        && ok "--refazer nao pula nada" || nok "T10 refazer pulou"

# ===========================================================================
caso "T11 --registro mostra o que ja foi enviado"
roda "$ORIGEM" --registro
contem "$SAIDA" "documentos/contrato.pdf" && ok "o registro lista os arquivos enviados" || nok "T11 registro"
contem "$SAIDA" "O registro fica em"      && ok "diz onde o registro mora" || nok "T11 caminho do registro"
((CODIGO == 0)) && ok "--registro sai com 0" || nok "T11 codigo=$CODIGO"

# ===========================================================================
caso "T12 outra pasta no Drive nao herda o registro da primeira"
roda "$ORIGEM" --drive-pasta OutraPasta -s
contem "$SAIDA" "Enviados ...... 14 de 14" && ok "envia tudo para a pasta nova, sem pular por registro antigo" || nok "T12 pulou indevido"
[[ -f "$DRIVE/OutraPasta/documentos/contrato.pdf" ]] && ok "os arquivos chegaram na pasta nova" || nok "T12 pasta nova vazia"
[[ -d "$DRIVE/MeuBackup" ]] && ok "a pasta anterior continua la" || nok "T12 apagou a anterior"

# ===========================================================================
caso "T13 arquivo chega cortado no Drive"
limpa; conecta
touch "$LAB/.corromper"
roda "$ORIGEM" --drive-pasta Cortado -s --incluir 'leia-me.txt'
rm -f "$LAB/.corromper"
contem "$SAIDA" "nao bate com o local" && ok "pega o arquivo truncado pelo tamanho" || nok "T13 nao pegou"
((CODIGO == 2)) && ok "sai com 2 quando teve falha" || nok "T13 codigo=$CODIGO"

# ===========================================================================
caso "T14 conteudo diferente no Drive, com o tamanho certo"
limpa; conecta
touch "$LAB/.hash-errado"
roda "$ORIGEM" --drive-pasta HashRuim -s --incluir 'leia-me.txt'
rm -f "$LAB/.hash-errado"
contem "$SAIDA" "o conteudo no Drive nao confere" && ok "o MD5 pega o byte trocado que o tamanho nao pega" || nok "T14 nao pegou"
((CODIGO == 2)) && ok "sai com 2" || nok "T14 codigo=$CODIGO"

# ===========================================================================
caso "T15 --por-data guarda historico, e a retencao roda"
limpa; conecta
roda "$ORIGEM" --drive-pasta Historico -s --por-data --incluir 'leia-me.txt'
N_DATAS="$(ls -d "$DRIVE/Historico"/[0-9]*_[0-9]* 2>/dev/null | wc -l | tr -d ' ')"
((N_DATAS == 1)) && ok "criou a pasta de data" || nok "T15 datas=$N_DATAS"
mkdir -p "$DRIVE/Historico/2020-01-01_0000" "$DRIVE/Historico/2021-01-01_0000"
printf 'velho\n' > "$DRIVE/Historico/2020-01-01_0000/x"
printf 'velho\n' > "$DRIVE/Historico/2021-01-01_0000/x"
roda "$ORIGEM" --drive-pasta Historico -s --por-data --drive-manter 2 --incluir 'leia-me.txt'
[[ ! -d "$DRIVE/Historico/2020-01-01_0000" ]] && ok "--drive-manter 2 apagou a data mais antiga" || nok "T15 nao apagou"
[[ -d "$DRIVE/Historico/2021-01-01_0000" ]] && ok "guardou a segunda mais nova" || nok "T15 apagou demais"

# ===========================================================================
caso "T16 --drive-manter sem --por-data e recusado"
roda "$ORIGEM" --drive-pasta X -s --drive-manter 3
contem "$SAIDA" "so faz sentido com --por-data" && ok "recusa a combinacao que nao faz sentido" || nok "T16 aceitou"
((CODIGO == 1)) && ok "sai com 1" || nok "T16 codigo=$CODIGO"

# ===========================================================================
caso "T17 nome de pasta no Drive: o que e recusado e o que e corrigido"
limpa; conecta
for n in 'com:doispontos' 'tem/../ponto-ponto' 'tem\barra-invertida'; do
  roda "$ORIGEM" --drive-pasta "$n" -s
  contem "$SAIDA" "--drive-pasta:" && ok "recusa o nome '$n'" || nok "T17 aceitou '$n'"
done
# barra sobrando na ponta e erro de digitacao comum, e nao vale parar o backup
# por causa dela: o script tira a barra e segue
roda "$ORIGEM" --drive-pasta '/Fotos/' -s --incluir 'leia-me.txt'
[[ -d "$DRIVE/Fotos" && -f "$DRIVE/Fotos/leia-me.txt" ]]   && ok "barra sobrando na frente e no fim e corrigida, nao recusada" || nok "T17 barra na ponta"

# ===========================================================================
caso "T18 origem que nao serve e recusada"
roda "/pasta/que/nao/existe/mesmo" --drive-pasta X -s
contem "$SAIDA" "nao achei essa pasta" && ok "pasta inexistente e recusada" || nok "T18 inexistente"
roda "/" --drive-pasta X -s
contem "$SAIDA" "a raiz do sistema nao e pasta de backup" && ok "a raiz / e recusada" || nok "T18 raiz"
roda "$ORIGEM/leia-me.txt" --drive-pasta X -s
contem "$SAIDA" "isso nao e uma pasta" && ok "arquivo em vez de pasta e recusado" || nok "T18 arquivo"

# ===========================================================================
caso "T19 estado dentro da origem e recusado"
roda "$ORIGEM" --drive-pasta X -s --estado "$ORIGEM/estado"
contem "$SAIDA" "nao pode ficar dentro da origem" && ok "recusa gravar o registro dentro da pasta copiada" || nok "T19 aceitou"
rm -rf "$ORIGEM/estado"

# ===========================================================================
caso "T20 sem conexao, e sem terminal para autorizar"
limpa; desconecta
roda "$ORIGEM" --drive-pasta X -s --incluir 'leia-me.txt'
contem "$SAIDA" "precisa de terminal" && ok "diz que a primeira autorizacao pede terminal" || nok "T20 mensagem"
contem "$SAIDA" "--conectar" && ok "ensina o comando --conectar" || nok "T20 ensina --conectar"
((CODIGO == 1)) && ok "sai com 1" || nok "T20 codigo=$CODIGO"

# ===========================================================================
caso "T21 sem --drive-pasta e sem terminal, usa o nome da pasta e avisa"
limpa; conecta
roda "$ORIGEM" -s --incluir 'leia-me.txt'
contem "$SAIDA" "sem terminal para perguntar" && ok "avisa que nao deu para perguntar o nome" || nok "T21 aviso"
[[ -d "$DRIVE/origem" ]] && ok "usou o nome da pasta de origem no Drive" || nok "T21 pasta"

# ===========================================================================
caso "T22 escrita do rclone.conf"
limpa; conecta
cat > "$LAB/rclone.conf" <<'CONF'
[outro-remote]
type = s3
provider = Minio
CONF
# a funcao de escrita e exercitada por um bash que carrega so ela
( export PATH="$LAB/bin:$PATH" HOME="$CASA"
  cd "$LAB"
  awk '/^# Autorizacao: um link/{exit} {print}' "$S" > "$LAB/so-funcoes.sh"
  printf '\nLOG=/dev/null\nDRIVE_REMOTE=avulso-drive\nCARIMBO=teste\n' >> "$LAB/so-funcoes.sh"
  printf 'escreve_remote_rclone "{\\"access_token\\":\\"abc\\"}" drive\n' >> "$LAB/so-funcoes.sh"
  bash "$LAB/so-funcoes.sh" >/dev/null 2>&1 ) || true
CONF_FINAL="$(cat "$LAB/rclone.conf" 2>/dev/null)"
contem "$CONF_FINAL" "[outro-remote]"   && ok "preserva o remote que ja existia" || nok "T22 apagou o outro remote"
contem "$CONF_FINAL" "[avulso-drive]"   && ok "grava a secao do remote novo" || nok "T22 nao gravou"
contem "$CONF_FINAL" "type = drive"     && ok "grava type = drive" || nok "T22 type"
nao_contem "$CONF_FINAL" "client_id"    && ok "nao grava client_id, para o rclone renovar com a chave dele" || nok "T22 client_id gravado"
nao_contem "$CONF_FINAL" "client_secret" && ok "nao grava client_secret" || nok "T22 client_secret gravado"

# ===========================================================================
caso "T23 trava contra duas execucoes ao mesmo tempo"
limpa; conecta
if command -v flock >/dev/null 2>&1; then
  roda "$ORIGEM" --drive-pasta Trava -s --incluir 'leia-me.txt'
  EST="$(pasta_estado)"
  (
    exec 9>"$EST/backup-avulso.lock"
    flock -n 9 || exit 1
    SAIDA2="$( cd "$LAB" && bash "$S" "$ORIGEM" --drive-pasta Trava -s --incluir 'leia-me.txt' 2>&1 )"
    grep -qF "ja existe um backup desta pasta em andamento" <<< "$SAIDA2"
  ) && ok "a segunda execucao e recusada enquanto a primeira tem a trava" \
    || nok "T23 a trava nao segurou"
else
  printf '        pulado: esta maquina nao tem flock\n'
fi

# ===========================================================================
caso "T24 a origem continua intacta depois de tudo"
# o T08 mudou dois arquivos de proposito; aqui a conferencia e que nada
# ALEM do que o teste mudou saiu diferente
rm -f "$ORIGEM/documentos/novo.txt"
printf 'contrato do cliente\n' > "$ORIGEM/documentos/contrato.pdf"
[[ "$(assina_origem)" == "$ASSINATURA_INICIAL" ]] \
  && ok "nenhum arquivo, atalho ou permissao da origem foi alterado pelo script" \
  || nok "T24 a origem mudou fora do que o teste mudou"

# ===========================================================================
printf '\n%s\n' "$(printf '%.0s=' {1..70})"
printf 'PASSOU: %s    REPROVOU: %s\n' "$PASSOU" "$REPROVOU"
if ((REPROVOU)); then
  printf '\nreprovadas:\n'
  for f in "${FALHAS[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'tudo verde\n'
exit 0
