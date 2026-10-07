# Backup de uma pasta para o Google Drive

Você aponta uma pasta. Ele manda os arquivos dela para uma pasta nova no seu
Google Drive, um por um, e confere cada um lá.

```bash
./backup-avulso.sh ~/Documentos
```

É isso. Ele pergunta o nome da pasta que vai criar no Drive, mostra quantos
arquivos e quanto vai subir, e espera você dizer sim.

## Três passos

**1. Baixe o script e dê permissão de execução**

```bash
curl -fsSLO https://raw.githubusercontent.com/wmenezes2020/backup-avulso-google-drive/main/backup-avulso.sh
chmod +x backup-avulso.sh
```

**2. Ligue o Google Drive, uma vez só**

```bash
./backup-avulso.sh --conectar
```

Ele mostra um link. Você abre no navegador, escolhe a conta Google, clica em
Permitir, copia a URL em que o navegador caiu e cola de volta no terminal.

A página vai dizer que não conseguiu acessar `127.0.0.1`. **Isso é o esperado.**
O endereço dela é a sua resposta. Copie a barra de endereço inteira.

Não precisa criar projeto no Google Cloud, nem chave, nem cartão de crédito.

**3. Rode o backup**

```bash
./backup-avulso.sh /caminho/da/pasta
```

## O que acontece na tela

```
==> Conferindo o terreno
  ok origem: /home/ana/Documentos
  ok prioridade baixa de CPU e disco, para nao travar a maquina

  Que nome vai ter a pasta criada no seu Google Drive?
  Enter aceita: Documentos
  Nome da pasta no Drive: Documentos-2026

==> Listando os arquivos de /home/ana/Documentos
  ok 412 arquivo(s), 1.8 GB no total

==> Criando a pasta no Google Drive
  ok pasta 'Documentos-2026' criada no Google Drive
  ok destino no Drive: avulso-drive:Documentos-2026

  Vou enviar 412 arquivo(s), 1.8 GB, de
    /home/ana/Documentos
  para
    avulso-drive:Documentos-2026
  Nada na pasta de origem e apagado nem alterado.

  Pode enviar? [s/N] s

[1/412] contratos/2026/aluguel.pdf  340.2 KB
[2/412] contratos/2026/seguro.pdf  1.1 MB
[3/412] fotos/praia.jpg  4.3 MB
...
=========================== BACKUP CONCLUIDO ===========================
  Enviados ...... 412 de 412
  Ja estavam .... 0
  Com erro ...... 0
  No Drive ...... avulso-drive:Documentos-2026
  Enviado ....... 1.8 GB
  Duracao ....... 14m 22s
```

## Se parar no meio, rode o mesmo comando outra vez

Cada arquivo que sobe deixa uma linha num registro. Na execução seguinte:

- arquivo que **não mudou** é pulado,
- arquivo que **mudou** sobe de novo,
- arquivo **novo** sobe.

Então, se a internet caiu no arquivo 300 de 900, é só repetir o comando. Ele
continua de onde parou.

```bash
./backup-avulso.sh ~/Documentos --registro   # mostra o que já subiu
./backup-avulso.sh ~/Documentos --refazer    # manda tudo de novo
```

O registro não decide sozinho: antes de pular um arquivo, o script **confere no
Drive** que ele está mesmo lá, do tamanho certo. Se alguém apagou do Drive, ele
sobe de novo.

## Antes de mandar, veja o que seria mandado

```bash
./backup-avulso.sh ~/Documentos --simular
```

Lista os arquivos, os tamanhos, o total, e o que os filtros deixaram de fora.
Não cria nada no Drive e não envia nada.

## A sua pasta não é tocada

O script só lê. Nada dentro da pasta de origem é apagado, movido, renomeado nem
alterado, e o registro e o relatório ficam fora dela, em
`$HOME/.backup-avulso/`.

## Receitas que resolvem a maioria dos casos

```bash
# só os PDFs e as planilhas
./backup-avulso.sh ~/Documentos --incluir '*.pdf' --incluir '*.xlsx'

# sem lixo de build e sem log
./backup-avulso.sh /var/www --excluir 'node_modules/*' --excluir '*.log'

# só o que está na raiz da pasta, sem entrar nas subpastas
./backup-avulso.sh ~/Downloads --sem-subpastas

# pular arquivo gigante
./backup-avulso.sh ~/Videos --max-mb 500

# cifrar antes de subir (quem não tem a senha não abre)
./backup-avulso.sh ~/Contratos --cifrar

# guardar histórico: cada execução numa pasta com data
./backup-avulso.sh ~/Documentos --por-data --drive-manter 7

# sem perguntar nada, para rodar no cron
./backup-avulso.sh ~/Documentos --drive-pasta Documentos -s
```

## Agendar

Depois de ter conectado uma vez, o script roda sozinho. No cron, passe o nome da
pasta do Drive e o `-s`, porque lá não tem ninguém para responder.

```bash
30 2 * * * /caminho/backup-avulso.sh /caminho/da/pasta --drive-pasta MeuBackup -s >> /tmp/backup-avulso.log 2>&1
```

## Trazer os arquivos de volta

Pelo site do Google Drive, baixando a pasta. Ou pelo rclone, que o script já
deixou configurado:

```bash
rclone copy avulso-drive:Documentos-2026 /caminho/onde/restaurar -P
```

Se você usou `--cifrar`, cada arquivo volta com `.gpg` no fim:

```bash
gpg --output arquivo.pdf --decrypt arquivo.pdf.gpg
```

Sem a senha não existe como abrir. Perdeu a senha, perdeu o backup.

## Todas as opções

| Opção | O que faz |
|---|---|
| `-p`, `--pasta DIR` | A pasta de origem, se preferir nomear a opção |
| `--drive-pasta P` | Nome da pasta no Drive, para não ser perguntado. Aceita caminho: `Backups/Fotos` cria as duas |
| `--sem-subpastas` | Só os arquivos da raiz da pasta |
| `--sem-ocultos` | Deixa de fora o que começa com ponto |
| `--incluir PADRÃO` | Só quem casa com o padrão. Pode repetir |
| `--excluir PADRÃO` | Deixa de fora quem casa com o padrão. Pode repetir |
| `--max-mb N` | Pula arquivo maior que N MB |
| `--seguir-atalhos` | Envia o conteúdo apontado pelo atalho simbólico |
| `--cifrar` | Cifra cada arquivo com AES256 antes de subir |
| `--senha-arquivo F` | Lê a senha da cifra do arquivo F |
| `--simular` | Lista o que subiria. Não envia nada |
| `-s`, `--sim` | Responde sim às perguntas (cron) |
| `--sem-nice` | Prioridade normal de CPU e disco |
| `--registro` | Mostra o que já foi enviado desta pasta |
| `--refazer` | Envia tudo de novo |
| `--estado DIR` | Onde ficam registro, log e relatório |
| `--conectar` | Liga o Drive e sai |
| `--reconectar` | Refaz a autorização |
| `--drive-remote N` | Nome do remote no rclone. Padrão `avulso-drive` |
| `--drive-escopo E` | `total` ou `arquivos` |
| `--por-data` | Cada execução numa subpasta `AAAA-MM-DD_HHMM` |
| `--drive-manter N` | Com `--por-data`, guarda as N datas mais novas |
| `-h`, `--ajuda` | A ajuda do script |

## O que o script precisa na máquina

- `bash` 4 ou mais novo (no macOS, `brew install bash`)
- `rclone`, que ele instala sozinho se faltar
- `curl`, para a autorização do Google
- `find`, `awk`, `sed`, `sort`, `stat`, `md5sum`

Sem `md5sum` ele ainda funciona, mas a conferência no Drive passa a ser só por
tamanho, e o relatório diz isso.

## Perguntas que aparecem

**Por que a página do Google dá erro?**
Porque o Google devolve o navegador para `127.0.0.1:53682`, e ninguém está
escutando ali. O que importa não é a página, é o endereço dela: ele traz o
código. Não existe jeito mais simples: as duas alternativas que pareceriam
melhores foram medidas contra a API do Google e as duas estão desligadas. Está
explicado em [docs/SDD_BACKUP_AVULSO.md](docs/SDD_BACKUP_AVULSO.md).

**O script apaga alguma coisa da minha pasta?**
Não. Ele só lê. O único lugar onde ele escreve é
`$HOME/.backup-avulso/` e a pasta que você escolheu no Drive.

**Arquivo com o mesmo nome no Drive é substituído?**
Sim, pela versão nova. Se você quer guardar as versões antigas, use
`--por-data`: cada execução vai para uma subpasta com a data.

**Pasta vazia sobe?**
Não existe pasta vazia no Google Drive: ele não guarda pasta sem arquivo. O
relatório lista quais ficaram de fora por isso.

**E atalho simbólico?**
Por padrão fica de fora, e aparece no relatório, para ninguém achar que o
conteúdo apontado subiu. Com `--seguir-atalhos` o conteúdo vai.

**Como ele sabe que o arquivo chegou certo?**
O Google Drive guarda e devolve o MD5 de cada arquivo. O script lê esse valor e
compara com o daqui, sem baixar nada. Quando o Drive não devolve hash, sobra a
comparação de tamanho, e o relatório diz qual das duas foi usada em cada caso.

**Posso enviar a mesma pasta para dois lugares diferentes do Drive?**
Pode. O registro guarda para onde cada arquivo foi, então mandar para uma pasta
nova envia tudo de novo, em vez de achar que já está pronto.

## Como validar o script

```bash
bash -n backup-avulso.sh      # sintaxe
bash scripts/monta-lab.sh     # monta um Google Drive de mentira
bash scripts/roda-testes.sh   # a bateria
```

## Documentos

- [PRD.md](PRD.md): o que o produto faz, e o que ele não faz
- [docs/SDD_BACKUP_AVULSO.md](docs/SDD_BACKUP_AVULSO.md): as decisões e o porquê
  de cada uma
- [CLAUDE.md](CLAUDE.md): as armadilhas deste código, descobertas na marra
- [graphify-out/graph.html](graphify-out/graph.html): o mapa do repositório

## Licença

MIT. Copyright (c) 2026 Wesley Menezes. Veja [LICENSE](LICENSE).
