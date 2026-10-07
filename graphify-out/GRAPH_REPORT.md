# Graph Report - BACKUP AVULSO  (2026-10-07)

## Corpus Check
- Corpus is ~19,638 words - fits in a single context window. You may not need a graph.

## Summary
- 84 nodes · 177 edges · 11 communities (10 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- backup-avulso.sh
- roda-testes.sh
- backup-avulso.sh script
- cria_pasta_drive
- gerar-grafo.py
- configura_drive
- lista_arquivos
- autoriza_por_link
- instala_rclone
- tem_terminal
- monta-lab.sh script

## God Nodes (most connected - your core abstractions)
1. `backup-avulso.sh script` - 28 edges
2. `configura_drive()` - 13 edges
3. `roda-testes.sh script` - 13 edges
4. `autoriza_por_link()` - 11 edges
5. `aviso()` - 9 edges
6. `instala_rclone()` - 9 edges
7. `cria_pasta_drive()` - 9 edges
8. `tem()` - 8 edges
9. `falha()` - 7 edges
10. `diz()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `backup-avulso.sh script` --calls--> `aviso()`  [EXTRACTED]
  backup-avulso.sh → backup-avulso.sh  _Bridges community 2 → community 8_
- `backup-avulso.sh script` --calls--> `configura_drive()`  [EXTRACTED]
  backup-avulso.sh → backup-avulso.sh  _Bridges community 2 → community 5_
- `backup-avulso.sh script` --calls--> `cria_pasta_drive()`  [EXTRACTED]
  backup-avulso.sh → backup-avulso.sh  _Bridges community 2 → community 3_
- `backup-avulso.sh script` --calls--> `le_do_tty()`  [EXTRACTED]
  backup-avulso.sh → backup-avulso.sh  _Bridges community 2 → community 9_
- `backup-avulso.sh script` --calls--> `lista_arquivos()`  [EXTRACTED]
  backup-avulso.sh → backup-avulso.sh  _Bridges community 2 → community 6_

## Import Cycles
- None detected.

## Communities (11 total, 1 thin omitted)

### Community 0 - "backup-avulso.sh"
Cohesion: 0.11
Nodes (10): ARQUIVOS, ATALHOS, AVISOS, ERROS, EXCLUIR, FORA, INCLUIR, LINHAS_RELATORIO (+2 more)

### Community 1 - "roda-testes.sh"
Cohesion: 0.21
Nodes (16): assina_origem(), caso(), conecta(), contem(), desconecta(), FALHAS, HOME, limpa() (+8 more)

### Community 2 - "backup-avulso.sh script"
Cohesion: 0.32
Nodes (8): ajuda(), apelido(), cifra_para_tmp(), id_da_origem(), mostra_registro(), registra(), backup-avulso.sh script, tem()

### Community 3 - "cria_pasta_drive"
Cohesion: 0.32
Nodes (8): arquivo_conf_rclone(), cria_pasta_drive(), envia_arquivo(), escreve_remote_rclone(), falha(), feito(), md5_local(), morre()

### Community 4 - "gerar-grafo.py"
Cohesion: 0.33
Nodes (6): json, pathlib, dentro_do_escopo(), main(), Gera o grafo do graphify deste repositorio em graphify-out/. Entrega sempre os…, sys

### Community 5 - "configura_drive"
Cohesion: 0.40
Nodes (6): configura_drive(), diz(), passo(), remote_ja_existe(), retencao_drive(), testa_remote()

### Community 6 - "lista_arquivos"
Cohesion: 0.40
Nodes (5): casa_padrao(), legivel(), lista_arquivos(), passa_filtros(), tamanho_arquivo()

### Community 7 - "autoriza_por_link"
Cohesion: 0.50
Nodes (4): autoriza_por_link(), escopo_codificado(), numero_json(), valor_json()

### Community 8 - "instala_rclone"
Cohesion: 0.50
Nodes (4): aviso(), instala_rclone(), ja_enviado(), pergunta_sim()

### Community 9 - "tem_terminal"
Cohesion: 0.67
Nodes (4): le_do_tty(), pede_nome_da_pasta(), tem_terminal(), valida_nome_drive()

## Knowledge Gaps
- **14 isolated node(s):** `INCLUIR`, `EXCLUIR`, `ARQUIVOS`, `ATALHOS`, `VAZIAS` (+9 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 27 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `backup-avulso.sh script` connect `backup-avulso.sh script` to `backup-avulso.sh`, `cria_pasta_drive`, `configura_drive`, `lista_arquivos`, `instala_rclone`, `tem_terminal`?**
  _High betweenness centrality (0.041) - this node is a cross-community bridge._
- **Why does `autoriza_por_link()` connect `autoriza_por_link` to `backup-avulso.sh`, `backup-avulso.sh script`, `cria_pasta_drive`, `configura_drive`, `instala_rclone`, `tem_terminal`?**
  _High betweenness centrality (0.005) - this node is a cross-community bridge._
- **What connects `INCLUIR`, `EXCLUIR`, `ARQUIVOS` to the rest of the system?**
  _14 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `backup-avulso.sh` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._