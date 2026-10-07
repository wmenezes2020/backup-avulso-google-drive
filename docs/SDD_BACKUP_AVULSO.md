# SDD: Backup de uma pasta para o Google Drive

Autoria: Wesley Menezes
Versão: 1.0.0
Data: 07/10/2026

## 1. Problema

Uma pessoa quer tirar uma pasta da máquina e deixar guardada no Google Drive. A
pasta tem centenas ou milhares de arquivos, com nomes de verdade (espaço,
acento, aspas), em subpastas de subpastas.

O que ela tem hoje:

- **arrastar e soltar no navegador**: funciona até a conexão cair, e aí não se
  sabe o que já subiu;
- **cliente de sincronização**: espelha os dois lados, então apagar no Drive
  apaga aqui, o que é o oposto de backup;
- **rclone na mão**: resolve, mas exige configurar remote, entender flags e saber
  o que `copy` faz de diferente de `sync`.

Em todos os casos, duas perguntas ficam sem resposta: **chegou tudo?** e **chegou
certo?**

## 2. Causas raiz que viraram requisito

### 2.1 Execução que morre no meio

Com 900 arquivos, a chance de a execução não terminar na primeira tentativa não é
pequena: internet oscila, a máquina hiberna, alguém fecha o terminal.

Requisito: cada arquivo que termina deixa rastro, e a execução seguinte usa esse
rastro para continuar. Sem isso, o backup grande nunca termina, porque sempre
recomeça.

### 2.2 Rastro que mente

Um registro dizendo "enviado" é uma promessa, não um fato. Se alguém apagou o
arquivo do Drive à mão, o registro continua dizendo que está lá.

Requisito: o registro diz onde o arquivo **deveria** estar, e quem decide é a
conferência no Drive. Esse é o caso mais caro de todos: a tela diria "já está" e
não existiria cópia nenhuma.

### 2.3 Envio sem conferência não é backup

Arquivo truncado no destino tem nome, data e aparência de arquivo bom. A pessoa
descobre no dia em que precisa dele.

Requisito: nenhum arquivo é contado como enviado sem conferência no destino. E a
conferência tem que ser honesta sobre o próprio nível: comparar tamanho pega
arquivo cortado, mas não pega byte trocado.

### 2.4 A pasta de origem é da pessoa, não do script

O medo que afasta gente de ferramenta de backup é concreto: ferramenta que
"organiza" a pasta, ou que apaga o local porque o remoto mudou.

Requisito: a origem é somente leitura. Nada é escrito, movido, renomeado nem
apagado dentro dela, e o próprio registro mora fora. Isso tem que ser
verificável, não prometido.

### 2.5 Autorização do Google numa máquina sem navegador

O servidor onde o backup roda não tem navegador, e a máquina onde a pessoa tem
navegador não é a que precisa do token. Qualquer fluxo que dependa de o
navegador e o script estarem na mesma máquina quebra aí.

E mesmo com navegador: criar projeto no Google Cloud, habilitar a API do Drive,
gerar credencial e passar pela tela de verificação é onde a maioria desiste.

### 2.6 Nome de arquivo de verdade quebra script de shell

`pasta com espaço/arquivo com acento ção.txt`, `com'aspas"duplas.txt`,
`$cifrão e crase\`.txt`. Script que monta lista de arquivos com `ls` ou com
`for f in $(find ...)` quebra em todos esses, e o jeito de quebrar é silencioso:
o arquivo simplesmente não sobe.

Requisito: a lista de arquivos tem que atravessar o script sem nunca passar por
divisão por espaço.

## 3. Objetivo

Um script bash único, sem dependência, que:

1. receba o caminho de uma pasta;
2. pergunte o nome da pasta que vai criar no Google Drive;
3. liste os arquivos daquela pasta;
4. crie a pasta no Drive;
5. envie um arquivo por vez, conferindo cada um no destino;
6. consiga ser rodado de novo e continuar de onde parou;
7. não toque na pasta de origem;
8. escreva um relatório que diga o que subiu, o que foi pulado, o que ficou de
   fora e por quê.

Critério de conclusão: a bateria verde contra um Google Drive de mentira, com a
assinatura da árvore de origem idêntica antes e depois.

## 4. Solução

### 4.1 Um arquivo por vez, sem compactar

Não existe `tar` aqui. Cada arquivo sobe como ele é, no mesmo caminho relativo
dentro da pasta do Drive.

Custa mais chamadas de rede que um pacote único, e isso é uma escolha
consciente. O que se ganha:

- no Drive os arquivos ficam navegáveis e baixáveis um a um, sem descompactar;
- a retomada é por arquivo, não por pacote: cair no arquivo 300 custa 300
  arquivos, não o pacote inteiro;
- não existe pico de disco local, porque nada é gerado (fora do `--cifrar`).

### 4.2 A lista de arquivos, sem passar por divisão de palavra

```bash
while IFS= read -r -d '' caminho; do
  rel="${caminho#"$ORIGEM"/}"
  ...
done < <(find ... -type f -print0 | ordena_z)
```

`-print0` e `read -d ''` separam por byte zero, que é o único byte que não pode
aparecer em nome de arquivo. Daí para frente o nome vive em variável, sempre
entre aspas.

O `ordena_z` existe porque `sort -z` é do GNU. No BSD ele não existe, e aí a
lista vai na ordem do `find`, que continua correta, só não fica alfabética. A
sonda é `printf '' | sort -z`, com entrada vazia: GNU aceita, BSD recusa a opção.

### 4.3 A pergunta vem antes do trabalho

A ordem da execução é:

1. confere comandos e a pasta de origem;
2. **pergunta o nome da pasta do Drive**;
3. monta a pasta de estado e toma a trava;
4. lista os arquivos;
5. conecta o Drive, e autoriza se for a primeira vez;
6. **cria a pasta no Drive**;
7. mostra o resumo e pede **uma** confirmação;
8. envia.

Perguntar o nome no passo 2, e não no 6, evita o caso ruim de listar mil
arquivos e só então travar numa pergunta. E criar a pasta no passo 6, depois de o
Drive já ter respondido, evita a pergunta que não leva a nada porque a conexão
não existia.

### 4.4 Uma confirmação, nunca uma por arquivo

Antes de começar, uma tela: quantos arquivos, quanto de dado, de onde para onde,
e a frase de que nada na origem é apagado. Um sim. Depois disso o script não
interrompe mais.

A alternativa, perguntar por arquivo, é inviável: o mesmo desenho que funciona
para sessenta itens vira tortura em novecentos.

### 4.5 Nome da pasta no Drive

O nome é validado antes de valer:

| Recusado | Motivo |
|---|---|
| vazio | não dá nome a nada |
| contém `:` | é o separador de remote do rclone, e o caminho viraria outra coisa |
| contém `..` | subiria um nível no Drive |
| contém `\` | barra invertida não é separador aqui, e o nome sairia estranho |
| quebra de linha ou tabulação | quebraria o registro, que é separado por tabulação |

Barra sobrando na frente ou no fim é **corrigida**, não recusada: `/Fotos/` vale
como `Fotos`. É erro de digitação comum, e não vale parar um backup por causa
dele. Barra no meio é aceita de propósito: `Backups/Fotos` cria as duas pastas.

Quando a pasta já existe no Drive com arquivo dentro, o script diz quantos
arquivos tem lá e pergunta se é para usar aquela mesma, avisando que arquivo de
mesmo nome vai ser substituído. Vazia, ele só informa e segue.

### 4.6 Retomada: o registro propõe, a conferência decide

Uma linha por arquivo enviado, separada por tabulação:

```
epoch  data_legivel  caminho_relativo  situacao  bytes  mtime  md5  destino
```

Para decidir se pula, o script exige **quatro** coisas ao mesmo tempo:

1. existe linha `ok` para aquele caminho relativo;
2. o tamanho de agora é igual ao gravado;
3. o mtime de agora é igual ao gravado;
4. o destino gravado começa com a pasta desta execução, **e** o arquivo está lá,
   do tamanho certo, conferido no próprio Drive.

Falhar qualquer uma manda enviar. Os motivos de cada uma:

- **2 e 3** pegam arquivo que mudou aqui. Cópia velha no Drive achando que está
  pronta é pior que não ter cópia, porque ninguém vai olhar de novo.
- **4, a parte do destino**, resolve o caso de a mesma pasta de origem ter sido
  enviada para dois lugares diferentes do Drive. As duas vezes caem no mesmo
  registro, porque a pasta de estado é chaveada pela origem. Sem essa checagem o
  arquivo seria pulado sem nunca chegar na pasta nova.
- **4, a parte da conferência**, é a que importa de verdade: registro apontando
  para arquivo apagado à mão viraria um arquivo pulado sem backup nenhum.

Com `--por-data` a pasta de destino muda a cada execução, então nada é pulado, e
isso é o comportamento certo: cada data é um retrato completo.

### 4.7 A pasta de estado é chaveada pela ORIGEM

```
$HOME/.backup-avulso/<nome-da-pasta>-<id>
```

onde `<id>` são 8 caracteres do sha1 do caminho absoluto da origem.

Chavear pela origem, e não pelo nome escolhido no Drive, é o que faz
`--registro /caminho/da/pasta` funcionar dando só o caminho. Se a chave fosse o
nome do Drive, a pessoa teria que lembrar o que digitou semanas atrás, e o
`--registro` mostraria vazio sem explicar por quê.

O preço dessa escolha é a necessidade da checagem de destino da seção 4.6. É um
preço pequeno, pago uma vez no código, contra uma confusão que aparece toda vez.

A pasta de estado dentro da origem é recusada: o backup copiaria o próprio
registro, e ele cresceria a cada execução.

### 4.8 Conferência: tamanho, e depois o MD5 que o Drive devolve

O Google Drive guarda e devolve o MD5 de cada arquivo, e o rclone lê esse valor.
Então dá para comparar o conteúdo **sem baixar nada**.

```
rclone size --json   ->  bytes no destino, compara com o local
rclone md5sum        ->  hash no destino, compara com o md5sum daqui
```

MD5 aqui é conferência de integridade, não de segurança: serve para pegar
arquivo truncado ou byte trocado no caminho.

Quando o Drive não devolve hash, sobra a comparação de tamanho, e o relatório
registra que pelo menos um arquivo ficou só nela. Isso importa: dizer "conferido"
sem dizer como dá à pessoa mais confiança do que ela tem direito.

A bateria prova as duas pontas, com um rclone de mentira que sabota de propósito:

- entrega o arquivo cortado, com tamanho 0: pego pela comparação de tamanho;
- entrega o tamanho certo com hash `000...0`: pego só pelo MD5, que é exatamente
  o caso que a comparação de tamanho não vê.

### 4.9 Autorização do Drive: um link, e a URL de volta

O script monta o link, a pessoa abre no navegador do computador dela, escolhe a
conta Google e clica em Permitir. O Google devolve o navegador para
`http://127.0.0.1:53682/`, que não tem ninguém escutando, então a página dá erro.
A pessoa copia a barra de endereço inteira e cola no terminal. O script extrai o
`code=` e troca por um token.

#### Por que existe um endereço de retorno, se ninguém escuta nele

Não existe autorização do Google sem `redirect_uri`, e as duas saídas que
pareceriam mais simples estão mortas. Isso foi **medido contra a API**, não
suposto:

| Tentativa | Resposta do Google |
|---|---|
| `urn:ietf:wg:oauth:2.0:oob`, que mostrava o código na tela com botão de copiar | `Error 400: invalid_request`, "not supported". Desligado em 2022, para toda chave |
| Fluxo de dispositivo (RFC 8628), código curto em `google.com/device` | `invalid_client`, "Invalid client type". A chave do rclone é de aplicativo de computador, e o escopo do Drive não entra nesse fluxo |

Então o loopback em `127.0.0.1:53682` não é escolha de design: é o que sobrou. A
página de erro no navegador faz parte do procedimento, e o texto na tela diz isso
**antes** de a pessoa clicar, como passo 4, não como aviso de problema.

Antes de propor "simplificar" isso de novo, repita as duas medições.

O `redirect_uri` é exatamente `http://127.0.0.1:53682/`, com barra. É o que o
rclone registra. O Google tolera variações de loopback hoje, mas depender de
tolerância é apostar.

#### PKCE

Quando houver `openssl`, a troca do código pelo token vai com PKCE S256. Protege
o único momento em que um código de autorização existe em claro.

#### A chave usada

A que já vem embutida no próprio rclone, publicada no código dele. Credencial de
aplicativo instalado não é confidencial por desenho, e é por usar essa que não
existe projeto no Google Cloud para criar, nem faturamento, nem tela de
verificação.

O token gravado no `rclone.conf` sai **sem** `client_id` e **sem**
`client_secret`, de propósito: assim o rclone usa a chave dele mesmo, inclusive
para renovar o acesso. Gravar campo vazio faria a renovação falhar na semana
seguinte, e aí o backup pararia sozinho sem ninguém perceber.

### 4.10 Nada de segredo na linha de comando

O código de autorização, o `client_secret`, o `code_verifier` do PKCE e a senha
da cifra vão para o `curl` e para o `gpg` **por arquivo**, com
`--data-urlencode campo@arquivo` e `--passphrase-file`. Argumento de linha de
comando aparece no `ps` para qualquer usuário da máquina.

### 4.11 Permissão nasce certa, não vira certa depois

`umask 077` no começo do script. O registro lista os nomes dos seus arquivos e
para onde eles foram; o relatório, a mesma coisa; o `rclone.conf` tem o token.

Nascer 600 é diferente de nascer 644 e virar 600 no `chmod` de depois: nesse meio
tempo qualquer usuário da máquina leria.

### 4.12 O que fica de fora aparece no relatório

Arquivo filtrado, arquivo grande demais, arquivo sem permissão de leitura, atalho
simbólico e pasta vazia. Cada um com o motivo.

Pasta vazia merece explicação própria: **o Google Drive não guarda pasta sem
arquivo**. Não é limitação do script. Listar isso evita a pessoa procurar a pasta
lá e achar que o backup falhou.

Atalho simbólico fica de fora por padrão porque seguir atalho pode arrastar
qualquer coisa de qualquer lugar do disco, inclusive um laço. Com
`--seguir-atalhos` o conteúdo apontado vai, e o relatório diz que foi assim.

## 5. Não objetivos

- Sincronizar nos dois sentidos. Arquivo que sai da pasta local continua no
  Drive, de propósito.
- Apagar qualquer coisa da origem, com qualquer opção.
- Rodar como serviço vigiando a pasta. É um comando que começa e termina.
- Compactar tudo num pacote único.
- Restaurar sozinho. O relatório escreve o `rclone copy` pronto.
- Falar com outro serviço de nuvem. O rclone fala, este script foi feito e
  testado para o Google Drive.

## 6. Decisões e o porquê

| Decisão | Por quê |
|---|---|
| Um arquivo por vez, sem `tar` | Navegável no Drive, retomada fina, sem pico de disco |
| Uma confirmação, não uma por arquivo | Perguntar por arquivo é inviável em novecentos |
| Pasta de estado chaveada pela origem | `--registro` funciona dando só o caminho |
| Checagem de destino em `ja_enviado` | É o preço da linha de cima, e sem ela a segunda pasta do Drive ficaria vazia |
| MD5 do Drive, com cair para tamanho | Conferência de conteúdo sem baixar nada, e honestidade quando não dá |
| Chave embutida do rclone | Sem projeto no Google Cloud, sem faturamento, sem verificação |
| Token sem `client_id` e sem `client_secret` | Para a renovação automática continuar funcionando |
| Segredo por arquivo, nunca por argumento | `ps` é legível por qualquer usuário |
| `umask 077` no começo | Permissão certa desde o nascimento do arquivo |
| Prioridade baixa de CPU e disco por padrão | Backup de 20 GB não pode travar a máquina da pessoa |
| Script em ASCII puro | Para não depender do locale da máquina de destino |
| Recusa clara de bash 3.2 | Melhor dizer na primeira linha do que quebrar no meio |
| Trava com `flock` | Duas execuções na mesma pasta disputariam o mesmo registro |
| `--simular` não toma a trava | Simulação é leitura, e tem que rodar com um backup em andamento |

## 7. Validação feita nesta entrega

```
bash -n backup-avulso.sh        sintaxe: ok
bash scripts/monta-lab.sh       lab montado
bash scripts/roda-testes.sh     78 verificações, 0 reprovadas, 5 puladas
```

Os 24 casos estão listados na seção 6 do [PRD.md](../PRD.md), com o que cada um
prova.

### 7.1 O que NÃO foi verificado, e por quê

| Item | Por que | Como fica |
|---|---|---|
| Atalho simbólico | O `ln -s` do MSYS sem privilégio copia o arquivo em vez de criar o atalho. O lab detecta, remove a cópia e pula os quatro casos, em vez de testar a coisa errada | 4 verificações puladas |
| Trava com `flock` | Esta máquina não tem `flock` | 1 verificação pulada |
| Permissão 600 | `chmod` não gruda em NTFS pelo MSYS | Não afirmado como verificado |
| Autorização do Google | Precisa de alguém clicando em Permitir numa tela do Google, e de terminal de verdade | Registrado como não testado |
| A pergunta interativa do nome | O caminho sem terminal está testado (T21). O caminho com terminal só uma pessoa digitando exercita | Parcialmente testado |

A honestidade aqui não é formalidade. O código de autorização veio de um script
que já roda em produção, mas "veio de onde funciona" não é teste, e nesta entrega
ele está registrado como não testado.

### 7.2 Defeitos que a construção pegou

Três coisas que estariam erradas em produção se não tivesse teste:

1. **Dois bytes zero literais no meio do script.** A sonda do `sort -z` nasceu
   como `printf 'b\0a\0'`, escrita por um gerador que interpretou `\0` como byte
   zero de verdade. O `bash -n` passava. O que denunciou foi o `grep` dizer
   "Binary file matches" ao procurar uma linha de texto no script. Trocado por
   `printf '' | sort -z`, que faz a mesma sonda sem precisar do byte.
2. **Linha duplicada na montagem do nome cifrado.** `nome_destino` era atribuído
   duas vezes em sequência, e a primeira versão estava errada. A segunda
   corrigia, então o resultado era certo por acidente. Removida.
3. **`sort -z` como dependência silenciosa.** Em máquina BSD o script sairia com
   erro na listagem, que é o primeiro passo do trabalho. Agora existe a sonda, e
   sem `sort -z` a lista só deixa de ser alfabética.

E dois casos em que **o teste estava errado, não o script**:

- a asserção de que o arquivo oculto não apareceria na tela com `--sem-ocultos`.
  Ele aparece de propósito, na lista do que ficou de fora, com o motivo. A
  asserção certa é essa;
- a asserção de que `--drive-pasta /comeca-com-barra` seria recusado. Barra na
  ponta é corrigida de propósito. O teste passou a conferir a correção.

Registrar isso importa porque a tentação, nos dois casos, é mexer no script até o
teste passar.
