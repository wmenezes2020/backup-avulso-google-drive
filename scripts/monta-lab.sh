#!/usr/bin/env bash
# Monta o laboratorio: uma pasta de origem com os casos tortos que aparecem na
# vida real, um rclone de mentira cujo "Drive" e uma pasta em disco, e uma HOME
# falsa para o registro e o relatorio nascerem dentro do lab.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
LAB="$REPO/.lab"

# no Windows uma pasta com processo dentro nao se apaga ("Device or resource
# busy"). Nesse caso ela sai da frente por rename, para o lab nascer limpo em
# vez de nascer pela metade e reprovar tudo por engano.
if [[ -e "$LAB" ]]; then
  rm -rf "$LAB" 2>/dev/null || mv "$LAB" "$LAB.velho.$(date +%s)" 2>/dev/null \
    || { echo "nao consegui limpar $LAB" >&2; exit 1; }
fi
[[ -e "$LAB" ]] && { echo "ainda existe $LAB" >&2; exit 1; }

mkdir -p "$LAB"/{bin,drive,casa,origem}
ORIGEM="$LAB/origem"

# ---------------------------------------------------------------------------
# pasta de origem
# ---------------------------------------------------------------------------
mkdir -p "$ORIGEM"/{documentos,fotos/2026,vazia,sub/mais/fundo,node_modules/pacote}

printf 'contrato do cliente\n' > "$ORIGEM/documentos/contrato.pdf"
printf 'planilha de custo\n'   > "$ORIGEM/documentos/custos.xlsx"
head -c 2048 /dev/urandom      > "$ORIGEM/fotos/2026/praia.jpg"
head -c 1024 /dev/urandom      > "$ORIGEM/fotos/2026/serra.jpg"
printf 'raiz da pasta\n'       > "$ORIGEM/leia-me.txt"
printf 'rascunho temporario\n' > "$ORIGEM/rascunho.tmp"
printf 'configuracao oculta\n' > "$ORIGEM/.configuracao"
printf 'fundo da arvore\n'     > "$ORIGEM/sub/mais/fundo/perdido.txt"
printf 'dependencia baixada\n' > "$ORIGEM/node_modules/pacote/indice.js"

# nomes tortos, que e onde script de shell costuma quebrar
mkdir -p "$ORIGEM/pasta com espaco"
printf 'acento e cedilha\n'   > "$ORIGEM/pasta com espaco/arquivo com acento cao.txt"
printf 'aspas no nome\n'      > "$ORIGEM/documentos/com'aspas\"duplas.txt"
printf 'cifrao e crase\n'     > "$ORIGEM/documentos/\$cifrao e crase\`.txt"

# arquivo grande, para o teste de --max-mb (3 MB)
head -c 3145728 /dev/zero > "$ORIGEM/fotos/grande.bin"

# atalho simbolico: por padrao fica de fora e aparece no relatorio.
# No Windows sem privilegio o ln -s do MSYS COPIA o arquivo em vez de criar o
# atalho, e ai o lab nasceria com um arquivo a mais se passando por atalho. Se o
# atalho nao sair atalho de verdade, ele e removido e o lab marca que o caso nao
# da para testar nesta maquina, em vez de testar a coisa errada.
ln -s ../leia-me.txt "$ORIGEM/documentos/atalho.txt" 2>/dev/null || true
if [[ -L "$ORIGEM/documentos/atalho.txt" ]]; then
  rm -f "$LAB/.sem-atalhos"
else
  rm -f "$ORIGEM/documentos/atalho.txt"
  : > "$LAB/.sem-atalhos"
  printf 'aviso: esta maquina nao cria atalho simbolico, os casos de atalho ficam de fora
'
fi

# ---------------------------------------------------------------------------
# rclone de mentira
# ---------------------------------------------------------------------------
cat > "$LAB/bin/rclone" <<'STUB'
#!/usr/bin/env bash
# rclone de mentira: o "Drive" e uma pasta em disco.
set -u
LAB="$(dirname "$(dirname "$0")")"
DRIVE="$LAB/drive"
CONF="$LAB/rclone.conf"

cmd="${1:-}"; shift || true

# descarta as flags conhecidas, guardando os argumentos de verdade
args=()
while (($#)); do
  case "$1" in
    --config|--drive-chunk-size|--retries|--low-level-retries|--stats|--log-level|--log-file|--transfers|--checkers) shift 2 ;;
    --stats-one-line|--json|--dirs-only) shift ;;
    --*) shift ;;
    *) args+=("$1"); shift ;;
  esac
done

caminho() {  # avulso-drive:a/b -> $DRIVE/a/b
  printf '%s' "$DRIVE/${1#*:}"
}

case "$cmd" in
  version)     echo "rclone v1.68.0-falso" ;;
  config)      [[ "${args[0]:-}" == file ]] && { echo "Configuration file is stored at:"; echo "$CONF"; } ;;
  listremotes) [[ -f "$LAB/.conectado" ]] && echo "avulso-drive:" ; exit 0 ;;
  lsd)         [[ -f "$LAB/.conectado" ]] || exit 1; mkdir -p "$DRIVE"; exit 0 ;;
  mkdir)
    p="$(caminho "${args[0]:-}")"
    mkdir -p "$p" || exit 1
    exit 0 ;;
  copyto)
    o="${args[0]:-}"; d="${args[1]:-}"
    dst="$(caminho "$d")"
    mkdir -p "$(dirname "$dst")" || exit 1
    cp -f "$o" "$dst" || exit 1
    # modo sabotagem: entrega o arquivo cortado, para testar a conferencia
    if [[ -f "$LAB/.corromper" ]]; then : > "$dst"; fi
    exit 0 ;;
  md5sum)
    p="$(caminho "${args[0]:-}")"
    [[ -f "$p" ]] || exit 0
    # modo sabotagem de conteudo: tamanho certo, hash errado
    if [[ -f "$LAB/.hash-errado" ]]; then
      printf '%s  %s\n' '00000000000000000000000000000000' "${p##*/}"
    else
      md5sum "$p" | awk -v n="${p##*/}" '{print $1"  "n}'
    fi
    exit 0 ;;
  size)
    p="$(caminho "${args[0]:-}")"
    if [[ -f "$p" ]]; then
      printf '{"count":1,"bytes":%s}\n' "$(stat -c%s "$p")"
      exit 0
    fi
    if [[ -d "$p" ]]; then
      n=0; b=0
      while IFS= read -r -d '' f; do
        n=$((n + 1)); b=$((b + $(stat -c%s "$f")))
      done < <(find "$p" -type f -print0 2>/dev/null)
      printf '{"count":%s,"bytes":%s}\n' "$n" "$b"
      exit 0
    fi
    # igual ao de verdade: caminho que nao existe sai com erro e nao imprime nada
    echo "directory not found" >&2
    exit 3 ;;
  lsf)
    p="$(caminho "${args[0]:-}")"
    [[ -d "$p" ]] || exit 0
    for e in "$p"/*; do [[ -d "$e" ]] && printf '%s/\n' "$(basename "$e")"; done
    exit 0 ;;
  purge)
    p="$(caminho "${args[0]:-}")"
    rm -rf "$p"; exit 0 ;;
  delete)
    p="$(caminho "${args[0]:-}")"
    rm -f "$p"; exit 0 ;;
  *) echo "rclone falso: comando nao previsto: $cmd" >&2; exit 64 ;;
esac
exit 0
STUB

chmod +x "$LAB/bin/"*

printf 'lab montado em %s\n' "$LAB"
printf 'origem com %s arquivo(s) e %s atalho(s)\n' \
  "$(find "$ORIGEM" -type f | wc -l | tr -d ' ')" \
  "$(find "$ORIGEM" -type l | wc -l | tr -d ' ')"
bash -n "$REPO/backup-avulso.sh" && printf 'sintaxe do script: ok\n'
