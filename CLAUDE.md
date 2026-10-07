# CLAUDE.md: Backup de uma pasta para o Google Drive

Memória deste repositório. Vale junto do `CLAUDE.md` global do usuário, que tem
precedência onde houver conflito.

## O que é este projeto

Um script bash, `backup-avulso.sh`, que recebe o caminho de uma pasta, pergunta
o nome da pasta que vai criar no Google Drive, e envia os arquivos daquela pasta
para lá, um por um, pelo rclone, conferindo cada um no destino.

Não tem build, não tem dependência de pacote, não tem instalação. A validação é
`bash -n` mais a bateria de testes contra um Google Drive simulado.

**A pasta de origem é somente leitura.** Nada é escrito, movido, renomeado nem
apagado dentro dela. O registro, o log e o relatório moram em
`$HOME/.backup-avulso/`. Qualquer mudança que ameace isso é regressão, e a
bateria tem duas verificações que comparam a assinatura da árvore inteira antes e
depois (T06 e T24).

## Passo zero de toda tarefa: o grafo

**Antes de escrever o SDD e antes de tocar no PRD, consultar o grafo do
graphify.** Não é para quando travar: é a primeira coisa, sempre.

```bash
graphify.exe query "<pergunta>"
graphify.exe explain "<coisa>"
graphify.exe path A B
```

Sem grafo no repositório, gerar antes de começar:

```bash
python scripts/gerar-grafo.py
```

**Nunca apagar `graphify-out/`.** Ele é versionado, entra no commit da tarefa, e
está fora de qualquer limpeza de disco. Refazer o mapa custa tempo a cada sessão,
e sessão sem mapa volta a abrir arquivo por arquivo.

No Git Bash desta máquina o comando é `graphify.exe`. Sem a extensão o shell acha
o arquivo sem extensão e o Python responde "can't open file", com saída vazia e
código de saída 0, o que parece sucesso.

## Como validar antes de commitar

```bash
bash -n backup-avulso.sh
bash scripts/monta-lab.sh
bash scripts/roda-testes.sh
```

Verde nos três antes de dar a tarefa por concluída.

## Armadilhas deste script, descobertas na marra

**Byte zero literal entra no script sem o `bash -n` reclamar.** A sonda do
`sort -z` nasceu como `printf 'b\0a\0'`, escrita por um gerador que interpretou
`\0` como byte zero de verdade. Sintaxe passava, e o que denunciou foi o `grep`
responder "Binary file backup-avulso.sh matches" ao procurar uma linha de texto.
Hoje a sonda é `printf '' | sort -z`, que não precisa do byte. **Ao gerar trecho
de script por script, conferir bytes de controle depois**, porque nenhum
validador de shell pega isso.

**`sort -z` é do GNU, e não existe no BSD.** Sem a sonda, o script sairia com
erro já na listagem, que é o primeiro passo do trabalho. A sonda usa entrada
vazia de propósito: GNU aceita a opção, BSD recusa, e nenhum dos dois precisa ler
nada.

**`stat` muda de sintaxe entre GNU e BSD.** `stat -c%s` no GNU, `stat -f%z` no
BSD. As duas funções de tamanho e de mtime tentam uma e caem na outra. Em Mac sem
isso o tamanho sai 0 e o script acha que todo arquivo está vazio.

**Array associativo, `mapfile` e `${var,,}` são de bash 4.** O bash do macOS é o
3.2, de 2007, e lá o script quebraria no meio com erro que não explica nada. A
checagem de versão está na primeira coisa que o script faz, antes de qualquer
declaração, e ensina `brew install bash`. Não tirar.

**A lista de arquivos nunca passa por divisão de palavra.** `find -print0` mais
`read -r -d ''`, e o nome vive em variável entre aspas daí para frente. O lab tem
nome com espaço, acento, aspas, cifrão e crase justamente porque o modo de
quebrar é silencioso: o arquivo simplesmente não sobe, sem erro nenhum.

**O padrão de `--incluir` e `--excluir` vai sem aspas de propósito.** É o `$p`
sem aspas dentro do `[[ ]]` que faz o glob valer. Com aspas, `*.pdf` só casaria
com um arquivo chamado literalmente `*.pdf`.

**A pasta de estado é chaveada pela ORIGEM, não pelo nome da pasta do Drive.**
Isso faz `--registro /caminho` funcionar dando só o caminho. O preço é a checagem
`[[ "$destino" == "$PASTA_DRIVE/"* ]]` dentro de `ja_enviado`: sem ela, enviar a
mesma pasta para uma segunda pasta do Drive pularia tudo e deixaria a pasta nova
vazia. As duas coisas andam juntas, não mexer em uma sem a outra.

**O registro nunca decide sozinho.** Ele diz onde o arquivo deveria estar; quem
decide é a conferência de que ele está mesmo lá, no Drive, do tamanho certo.
Registro apontando para arquivo apagado à mão viraria um arquivo pulado sem
backup nenhum, que é o pior resultado possível: a tela diria "já está" e não
existiria cópia alguma.

**Pular por tamanho só não basta: o mtime também entra.** Arquivo editado que
manteve o mesmo tamanho existe, e é comum em arquivo de configuração. Com só o
tamanho, a cópia velha ficaria no Drive para sempre, achando que está pronta.

**`client_id` e `client_secret` ficam de fora do `rclone.conf` de propósito.**
Assim o rclone usa a chave embutida nele, inclusive para renovar o acesso. Gravar
campo vazio faz a renovação falhar na semana seguinte, e aí o backup para sozinho
sem ninguém perceber.

**Não existe autorização do Google sem `redirect_uri`, e as duas saídas que
pareceriam mais simples estão mortas.** Foram medidas contra a API, não supostas:

| Tentativa | Resposta do Google |
|---|---|
| `urn:ietf:wg:oauth:2.0:oob`, que mostrava o código na tela com botão de copiar | `Error 400: invalid_request`, "not supported". Desligado em 2022, para toda chave |
| Fluxo de dispositivo (RFC 8628), código curto em `google.com/device` | `invalid_client`, "Invalid client type". A chave do rclone é de aplicativo de computador, e o escopo do Drive não entra nesse fluxo |

Então o loopback em `127.0.0.1:53682` não é escolha de design: é o que sobrou. A
página de erro no navegador faz parte do procedimento, e o texto na tela diz isso
antes de a pessoa clicar, como passo 4, não como aviso de problema. Antes de
propor "simplificar" isso de novo, repita as duas medições.

**O `redirect_uri` é exatamente `http://127.0.0.1:53682/`, com barra.** É o que o
rclone registra. O Google tolera variações de loopback hoje, mas depender de
tolerância é apostar.

**Pasta vazia não existe no Google Drive.** Ele não guarda pasta sem arquivo. Não
é defeito do script, e por isso a lista das vazias aparece no relatório: sem
isso a pessoa procura a pasta lá, não acha, e conclui que o backup falhou.

**`rclone size` num caminho que não existe sai com erro e não imprime nada.** O
rclone de mentira do lab imita isso de propósito (código 3, saída vazia). Quem
chama tem que tratar a saída vazia, porque é por ela que o script descobre que a
pasta do Drive ainda não existe.

**`ln -s` do MSYS sem privilégio COPIA o arquivo em vez de criar o atalho.** O
lab detecta isso, remove a cópia e grava `.lab/.sem-atalhos`, e a bateria pula os
quatro casos de atalho. Sem essa detecção o lab nasceria com um arquivo a mais se
passando por atalho, e os testes dariam verde testando a coisa errada.

**`rm -rf` em pasta com processo dentro falha no Windows** ("Device or resource
busy"). O montador do lab tira a pasta da frente por rename quando isso acontece,
porque lab pela metade reprova a bateria inteira por engano.

**Duas execuções da bateria ao mesmo tempo dão resultado falso.** Elas disputam o
mesmo `.lab/drive` e as asserções de uma leem o estado da outra. Uma rodada por
vez, e nada de mexer no repositório enquanto ela corre. É a mesma razão de o
script de produção tomar uma trava com `flock`.

**Teste que falha pode estar errado.** Dois casos nesta entrega: a asserção de
que o arquivo oculto não apareceria na tela com `--sem-ocultos` (ele aparece de
propósito, na lista do que ficou de fora, com o motivo) e a de que
`--drive-pasta /comeca-com-barra` seria recusado (barra na ponta é corrigida de
propósito). Nos dois a tentação era mexer no script até o teste passar. Confira
qual dos dois está descrevendo o comportamento certo antes de corrigir.

## Regras de ouro que se aplicam aqui

- **Travessão proibido** em tudo que uma pessoa lê: README, PRD, SDD, ajuda do
  script, mensagem de saída. Vale também para meia-risca e sinal de menos.
- **Sem acento no script.** `backup-avulso.sh` escreve em ASCII, para não
  depender do locale da máquina. Os documentos em Markdown usam acento normal.
- **Nunca indicar concorrente.** Recurso que falta vira item do PRD, com o ganho
  para o cliente.
- **Repositório público:** licença MIT, autoria apenas "Wesley Menezes", nenhuma
  citação interna (nome de cliente, de produto nosso ou de concorrente). As
  skills versionadas em `.claude/skills/` entram redigidas, e o hook de
  SessionStart pode desfazer a redação: **conferir antes de todo commit**.
- **PRD e SDD na mesma entrega.** Toda mudança de comportamento atualiza
  `PRD.md` e `docs/SDD_BACKUP_AVULSO.md`.
- **Commit e push a cada funcionalidade entregue**, com SDD, PRD, este arquivo,
  as skills versionadas e o `graphify-out/` regerado no mesmo commit.
- **`git pull` antes de todo `git push`.** Nunca apagar branch, tag, commit ou
  stash.
- **Honestidade na validação.** O que não foi testado é dito como não testado. A
  máquina de desenvolvimento é Windows, então atalho simbólico, permissão POSIX e
  `flock` não são verificáveis aqui, e o PRD registra isso.

## Estado atual

Versão 1.0.0, implementada. Bateria em 24 casos, 78 verificações, 0 reprovadas, 5
puladas nesta máquina (4 de atalho simbólico, 1 de `flock`).

Pendente: a primeira execução contra o Google Drive de verdade, que é o único
lugar onde a autorização, a renovação do token e o comportamento do Drive com
arquivo grande existem.
