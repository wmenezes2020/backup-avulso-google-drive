# PRD: Backup de uma pasta para o Google Drive

Autoria: Wesley Menezes
Versão: 1.0.0
Data: 07/10/2026

## 1. Para que serve

Um script que recebe o caminho de uma pasta, pergunta o nome da pasta que vai
criar no Google Drive, e envia os arquivos daquela pasta para lá, um por um,
conferindo cada um no destino.

O usuário é uma pessoa que precisa tirar uma pasta da máquina e deixar no Drive
sem aprender ferramenta nova, sem criar conta em serviço, sem configurar
credencial e sem ler manual. Um comando, uma pergunta, uma confirmação.

## 2. Problema que resolve

Guardar uma pasta no Google Drive parece simples até a pasta ter mil arquivos.
Aí aparecem os problemas que o arrastar e soltar não resolve:

1. **A conexão cai no meio.** Com 900 arquivos, parar no 300 e ter que começar
   do zero é inaceitável. Quem não tem como retomar desiste do backup.
2. **Ninguém confere se chegou.** Arquivo que sobe truncado fica no Drive
   parecendo um arquivo bom. A pessoa descobre no dia em que precisa dele.
3. **Autorizar o Google é a parte que trava todo mundo.** Criar projeto no
   Google Cloud, habilitar API, gerar chave e passar por tela de verificação faz
   a maioria parar antes do primeiro backup.
4. **Medo de perder o original.** Ferramenta de sincronização apaga arquivo do
   lado local quando ele sai do remoto. Quem já se queimou com isso não confia
   mais.
5. **Não se sabe o que subiu.** Sem relatório, "deu certo" é uma suposição.

## 3. Entregas

### 3.1 `backup-avulso.sh`

Script bash único, sem dependência de pacote, sem build, sem instalação.

**Fluxo principal**

| Passo | O que faz |
|---|---|
| 1 | Confere que os comandos existem e que a origem é uma pasta legível |
| 2 | Pergunta o nome da pasta que vai nascer no Google Drive |
| 3 | Lista os arquivos da origem, aplicando os filtros |
| 4 | Conecta o Drive. Na primeira vez, conduz a autorização |
| 5 | Cria a pasta no Drive com o nome escolhido |
| 6 | Mostra quantos arquivos, quanto de dado, e pede uma confirmação |
| 7 | Envia um arquivo por vez, conferindo cada um no destino |
| 8 | Escreve o relatório, e manda uma cópia dele para o Drive |

**Garantias**

- A pasta de origem nunca é escrita, movida, renomeada nem apagada. O script só
  lê dela. Isso é verificado na bateria, comparando a assinatura da árvore
  inteira antes e depois.
- Nenhum arquivo é considerado enviado sem conferência no destino. Primeiro o
  tamanho, depois o MD5 que o próprio Google Drive devolve. O relatório diz qual
  das duas valeu, para ninguém achar que teve mais garantia do que teve.
- O registro das linhas enviadas e o relatório nascem com permissão 600, e ficam
  fora da pasta de origem.
- Nenhum segredo passa pela linha de comando: o código de autorização, o segredo
  do cliente e a senha da cifra vão por arquivo, não por argumento.

**Retomada**

Toda linha enviada fica em `$HOME/.backup-avulso/<pasta>-<id>/registro.tsv`:
epoch, data legível, caminho relativo, situação, bytes, mtime, MD5 e destino.

Na execução seguinte, para cada arquivo:

- não mudou (mesmo tamanho e mesmo mtime) **e** está no Drive do tamanho certo
  → pulado;
- mudou aqui → enviado de novo;
- sumiu do Drive → enviado de novo, com aviso;
- o registro aponta para outra pasta do Drive → enviado, porque é outro destino.

O registro nunca decide sozinho. Ele diz onde o arquivo deveria estar, e a
conferência no Drive diz se ele está. Registro apontando para arquivo apagado à
mão viraria um arquivo pulado sem cópia nenhuma, que é o pior resultado
possível.

**Filtros**

`--incluir`, `--excluir` (os dois repetíveis, casando com o nome ou com o
caminho relativo), `--sem-ocultos`, `--sem-subpastas`, `--max-mb`,
`--seguir-atalhos`.

Todo arquivo que fica de fora aparece no relatório com o motivo. Pasta vazia e
atalho simbólico também, porque o Google Drive não guarda pasta sem arquivo e
porque ninguém deve supor que o conteúdo de um atalho subiu.

**Extras**

- `--simular`: lista e soma, não cria pasta no Drive e não envia nada.
- `--cifrar`: AES256 por gpg, ou openssl quando não houver gpg.
- `--por-data`: cada execução numa subpasta `AAAA-MM-DD_HHMM`.
- `--drive-manter N`: com `--por-data`, guarda as N datas mais novas.
- `--conectar` e `--reconectar`: a autorização do Drive, sozinha.
- `--registro`: mostra o que já subiu daquela pasta.

### 3.2 Bateria de testes

`scripts/monta-lab.sh` monta uma pasta de origem com os casos tortos da vida
real (subpasta de subpasta, nome com espaço e acento, nome com aspas, nome com
cifrão e crase, arquivo oculto, pasta vazia, arquivo de 3 MB, atalho simbólico)
e um rclone de mentira cujo Google Drive é uma pasta em disco, com modo de
sabotagem para entregar arquivo cortado e para devolver hash errado.

`scripts/roda-testes.sh` roda 24 casos.

### 3.3 Documentação

`README.md` no padrão de três passos, `PRD.md`, `docs/SDD_BACKUP_AVULSO.md`,
`CLAUDE.md` com as armadilhas do código, e o grafo do repositório em
`graphify-out/`.

## 4. Fora de escopo

O que este produto deliberadamente não faz, e por quê:

- **Não sincroniza nos dois sentidos.** Arquivo que sai da pasta local continua
  no Drive. Apagar do Drive por conta própria é exatamente o comportamento que
  faz as pessoas perderem confiança em ferramenta de backup.
- **Não apaga nada da origem.** Em nenhuma circunstância, com nenhuma opção.
- **Não roda como serviço nem fica vigiando a pasta.** É um comando que começa e
  termina, e o cron resolve a repetição.
- **Não comprime em um único pacote.** O pedido é arquivo por arquivo, e isso
  tem uma vantagem concreta: no Drive os arquivos ficam navegáveis e baixáveis um
  a um, sem precisar descompactar nada.
- **Não restaura sozinho.** A volta é pelo site do Drive, ou pelo `rclone copy`
  que o relatório já escreve pronto.
- **Não lê outro serviço de nuvem.** O transporte é o rclone, que fala com vários
  destinos, mas este script foi feito e testado para o Google Drive.

## 5. Decisões de produto e o porquê

**A pergunta do nome da pasta vem antes de qualquer trabalho.**
Quem roda o script já sabe onde quer guardar. Perguntar no começo e não no fim
evita o caso ruim: listar mil arquivos, calcular tudo, e só então descobrir que
a pessoa não sabia responder.

**Uma confirmação, não uma por arquivo.**
Perguntar conta por conta funciona para sessenta contas. Para novecentos
arquivos, perguntar por arquivo é tortura. Então: uma tela com quantos arquivos,
quanto de dado, de onde para onde, e um sim. Depois disso o script não interrompe
mais.

**O padrão é entrar nas subpastas e repetir a estrutura no Drive.**
É o que a pessoa espera ao dizer "manda essa pasta". `--sem-subpastas` existe
para quem quer o contrário.

**Arquivo que mudou sobe de novo, sem perguntar.**
Mudou o conteúdo, a cópia no Drive está velha. Backup com cópia velha achando que
está pronto é pior que backup que não existe.

**A pasta de estado é chaveada pela origem, não pela pasta do Drive.**
Assim `--registro /caminho/da/pasta` funciona dando só o caminho, sem a pessoa
ter que lembrar o nome que digitou no Drive semanas atrás. O que impede um
registro de uma pasta do Drive de valer para outra é a conferência do destino na
hora de decidir pular.

**A conferência é o que autoriza dizer "enviado".**
MD5 lido do próprio Drive, sem baixar nada. Quando o Drive não devolve hash, cai
para tamanho, e isso aparece no relatório. Honestidade sobre o nível da garantia
vale mais que uma mensagem bonita.

**A autorização do Google usa a chave que já vem embutida no rclone.**
Credencial de aplicativo instalado não é confidencial por desenho. É por usar
essa chave que não existe projeto no Google Cloud para criar, nem faturamento,
nem tela de verificação. O token gravado sai sem `client_id` e sem
`client_secret`, para o rclone renovar o acesso com a chave dele mesmo.

**Prioridade baixa de CPU e disco por padrão.**
Backup de 20 GB não pode deixar a máquina da pessoa inutilizável. `--sem-nice`
existe para quem quer velocidade.

**O script é ASCII puro.**
Para não depender do locale da máquina onde ele vai rodar. Os documentos em
Markdown usam acento normal.

## 6. Validação feita nesta entrega

```
bash -n backup-avulso.sh                  sintaxe: ok
bash scripts/monta-lab.sh                 lab montado
bash scripts/roda-testes.sh               78 verificações, 0 reprovadas
```

**O que a bateria cobre, em 24 casos**

| Caso | O que prova |
|---|---|
| T01 | Acha os arquivos da árvore, inclusive nome com espaço e acento. Avisa atalho, pasta vazia, e que só lê. `--simular` não cria nada |
| T02 | `--sem-ocultos`, `--sem-subpastas`, `--incluir`, `--excluir` por nome e por caminho, `--max-mb`, `--seguir-atalhos` |
| T03 | Cria no Drive a pasta com o nome escolhido, e envia todos |
| T04 | Cada arquivo chega byte a byte igual, no mesmo caminho relativo. Nome com espaço, acento, aspas, cifrão e crase sobrevive. Pasta vazia não é criada. Atalho não sobe |
| T05 | Relatório escrito, com contagem e com a conferência usada, listando pasta vazia e atalho. Sobe para `_relatorios`. Não é escrito dentro da origem |
| T06 | A árvore de origem está idêntica à de antes do backup |
| T07 | Segunda execução pula os 13 que não mudaram, e não reenvia nada |
| T08 | Arquivo que mudou sobe de novo e substitui o velho no Drive. Arquivo novo sobe. Os outros continuam pulados |
| T09 | Arquivo apagado do Drive à mão é percebido e volta a subir |
| T10 | `--refazer` reenvia todos, sem pular nenhum |
| T11 | `--registro` lista o que subiu e diz onde o registro mora |
| T12 | Outra pasta no Drive não herda o registro da primeira: envia tudo |
| T13 | Arquivo que chega cortado é pego pelo tamanho, e o script sai com 2 |
| T14 | Conteúdo trocado com o tamanho certo é pego pelo MD5 |
| T15 | `--por-data` cria a pasta de data, e `--drive-manter` apaga a mais antiga guardando as N mais novas |
| T16 | `--drive-manter` sem `--por-data` é recusado |
| T17 | Nome de pasta com dois-pontos, com `..` e com barra invertida é recusado. Barra sobrando na ponta é corrigida, não recusada |
| T18 | Pasta inexistente, a raiz `/` e arquivo em vez de pasta são recusados |
| T19 | Pasta de estado dentro da origem é recusada |
| T20 | Sem conexão e sem terminal, diz que a primeira autorização pede terminal e ensina `--conectar` |
| T21 | Sem `--drive-pasta` e sem terminal, usa o nome da pasta de origem e avisa |
| T22 | O `rclone.conf` ganha a seção nova sem perder a que já existia, e sem `client_id` nem `client_secret` |
| T23 | A trava recusa duas execuções ao mesmo tempo |
| T24 | Nenhum arquivo, atalho ou permissão da origem foi alterado pelo script |

### 6.1 O que NÃO foi verificado, e por quê

Honestidade sobre o alcance da validação. A máquina de desenvolvimento é
Windows, e três coisas não existem lá do mesmo jeito:

| Item | Por que não dá para verificar aqui | Como fica |
|---|---|---|
| Atalho simbólico | O `ln -s` do MSYS sem privilégio **copia** o arquivo em vez de criar o atalho. O lab detecta isso, remove a cópia e pula os quatro casos de atalho, em vez de testar a coisa errada e dar verde falso | 4 verificações puladas |
| Trava com `flock` | Não existe `flock` nesta máquina | 1 verificação pulada |
| Permissão 600 | O chmod não gruda em NTFS pelo MSYS | Não afirmado como verificado |

O **fluxo de autorização do Google** também não é exercitado pela bateria: ele
precisa de alguém clicando em Permitir numa tela do Google e de um terminal de
verdade. O que a bateria cobre é tudo em volta dele: o caso sem terminal, a
escrita do `rclone.conf`, e a preservação das outras seções. A troca do código
pelo token é código herdado de um script já em produção, mas aqui ele está
**registrado como não testado**, não como testado.

**A pergunta interativa do nome da pasta** (`pede_nome_da_pasta`) tem o caminho
sem terminal testado (T21). O caminho com terminal, que lê a resposta e valida
em laço até o nome servir, só pode ser exercitado por uma pessoa digitando.

## 7. Próximos passos sugeridos

Itens que ainda não existem, com o ganho de cada um. Nenhum deles é necessário
para a versão 1.0.0 fazer o que foi pedido.

1. **Envio paralelo, com limite configurável.** Hoje é um arquivo por vez, o que
   é previsível e fácil de conferir, mas numa pasta com milhares de arquivos
   pequenos o tempo é dominado por latência, não por banda. Ganho: pasta com
   10 mil arquivos pequenos terminando em minutos em vez de horas.
2. **Barra de progresso com previsão de término.** Hoje a tela diz `[300/900]`.
   Ganho: a pessoa sabe se dá tempo de fechar o notebook.
3. **Relatório do que está no Drive e não está mais aqui.** Sem apagar nada,
   apenas listando. Ganho: dá para decidir à mão o que limpar, sem o risco de
   sincronização automática.
4. **Verificação periódica do que já subiu.** Um modo que relê o MD5 de uma
   amostra do que está no Drive e compara com o registro. Ganho: descobrir
   corrupção silenciosa antes de precisar do arquivo.
5. **Aviso por e-mail ou webhook ao terminar.** Ganho: backup no cron que falha
   em silêncio é backup que não existe, e hoje a descoberta depende de alguém
   abrir o log.
6. **Suporte a bash 3.2.** Hoje o script exige bash 4 e recusa claramente o 3.2
   do macOS, ensinando `brew install bash`. Ganho: rodar no macOS de fábrica,
   sem instalar nada.
