# Decisões do projeto

Cada decisão tem um código (D1, D2...), usado como referência no README. Para cada uma: o que foi escolhido, por quê, quais as alternativas e como ativá-las. Sempre que foi possível, a alternativa foi **implementada** atrás de uma variável do dbt (`--vars`) ou de um target, e **validada** com dbt-core 1.12.5 e dbt-duckdb 1.11.0 (Postgres com dbt-postgres 1.11.0 e Postgres 16).

## Resumo

| # | Decisão | Padrão | Alternativas implementadas | Como ativar |
|---|---|---|---|---|
| D1 | Versões | dbt-core 1.12.5, dbt-duckdb 1.11.0, fixas | (nenhuma) | |
| D2 | Materializações | staging e intermediate `view`, marts `table`, fact `incremental` | ephemeral: não (ver abaixo) | |
| D3 | Severidade do teste singular | `warn` + `store_failures` | `error`; limiares `warn_if`/`error_if` | `--vars '{negative_position_severity: error}'` |
| D4 | Onde ficam os testes | fonte `warn`, camadas `error` | fonte `error` | `--vars '{source_quality_severity: error}'` |
| D5 | Banco | DuckDB | Postgres | `--target postgres` |
| D6 | Pacotes | nenhum (sem `dbt deps`) | (nenhuma) | |
| D7 | Tipos dos seeds | tudo texto, tipagem no staging | (nenhuma) | |
| D8 | Limpeza das transações | filtrar inválidos no staging | (nenhuma) | |
| D9 | T035/T036 | manter as duas e marcar | deduplicar pelo conteúdo | `--vars '{dedup_transactions_by_content: true}'` |
| D10 | Clientes duplicados | manter o registro mais completo (SCD tipo 1) | SCD tipo 2 com snapshot (documentado, não implementado) | |
| D11 | Posições negativas no mart | não filtrar | filtrar (rejeitada, só demonstração) | `--vars '{portfolio_hide_negative_positions: true}'` |
| D12 | Significado de `net_amount` | posição líquida em valor financeiro (BUY − SELL) | (nenhuma) | |
| D13 | Incremental | `delete+insert` com janela de 3 dias | tamanho da janela | `--vars '{fact_lookback_days: 7}'` |
| D14 | Macros | `clean_string`, `deduplicate`, `count_nulls` + 2 testes genéricos | (nenhuma) | |
| D15 | Profile | `profiles.yml` na raiz | caminho do banco por env var | `DBT_DUCKDB_PATH=outro.duckdb` |
| D16 | Contratos nos marts | aplicados | (nenhuma) | |
| D18 | Descrições repetidas | doc blocks (`models/docs.md`) | (nenhuma) | |
| D19 | CI | GitHub Actions, DuckDB e Postgres | (nenhuma) | |
| D20 | Comando de execução | `seed`, `run`, `test` | `dbt build` | `dbt build` |
| D21 | Chave da dimensão | `client_id` original | surrogate key e SCD tipo 2 (não implementadas, ver D10 e D21) | |
| D22 | De onde os marts leem | portfólio e atividade da `dim_clients` leem da fato (Kimball) | ler do intermediate (não implementada) | |

**Resultado esperado no padrão:** `dbt seed`, `dbt run` e `dbt test` saem com código 0. O `dbt test` mostra `PASS=52 WARN=6 ERROR=0`. Os 6 avisos são os defeitos plantados (detalhados no README).

---

## D1. Versões fixas

**Escolha:** `requirements.txt` com `dbt-core==1.12.5` e `dbt-duckdb==1.11.0`. Python 3.10 ou mais novo.

**Por quê:** o critério eliminatório é rodar seguindo o README. Uma versão nova do dbt pode mudar sintaxe (o dbt 1.10 já mudou o formato dos testes genéricos para `arguments:`). Fixar versão elimina essa variável. O CI prova que essas versões funcionam num ambiente limpo.

## D2. Camadas e materializações

| Camada | Materialização | Por quê |
|---|---|---|
| staging | view | Barata e sempre reflete o seed. |
| intermediate | view | Pode ser testada e consultada para depurar. |
| `fact_transactions` | incremental | Bônus 6 (D13). |
| `dim_clients`, `mart_client_portfolio` | table | Consumo analítico, leitura rápida. |

**Alternativa não implementada:** intermediate como `ephemeral`. O dbt não permite testar nem consultar um modelo ephemeral, então os testes de `int_transactions` deixariam de existir. Perde-se mais do que se ganha num projeto deste tamanho.

## D3. Severidade do teste singular (a decisão central)

O enunciado pede duas coisas que, ao pé da letra, se contradizem: "tudo tem que passar" no `dbt test` e "o teste singular deve detectar o problema". Um teste que encontra linhas falha, e este encontra 6.

**Escolha:** severidade `warn` por padrão, controlada por variável, com `store_failures: true`.

```
WARN 6 assert_no_negative_position
Done. PASS=52 WARN=6 ERROR=0     (código de saída 0)
```

As 6 linhas ficam gravadas em `main_dbt_test__audit.assert_no_negative_position`.

**Por quê:**
1. Atende as duas frases: o teste detecta (aviso amarelo, contagem, linhas gravadas) e o comando passa.
2. É o mecanismo que o dbt oferece para isso. `error` quer dizer "o contrato do meu modelo quebrou"; `warn` quer dizer "há um problema conhecido na fonte que alguém precisa ver".
3. Protege o critério eliminatório.
4. Trocar para bloqueante é um `--vars`, sem editar código.

**Alternativas:**

| Alternativa | Status | Como |
|---|---|---|
| `error` fixo | Implementada e validada: código 1 | `dbt test --vars '{negative_position_severity: error}'` |
| Limiares (avisa até N, falha acima) | Implementada e validada | `dbt test --vars '{negative_position_severity: error, negative_position_error_if: ">10"}'` |
| Filtrar negativas no mart | Implementada só para demonstrar por que é rejeitada (D11) | |
| Corrigir os CSVs | Não implementada: o enunciado proíbe | |

Um detalhe que o teste das alternativas revelou: **limiares só funcionam com severidade `error`**. Com `warn`, o dbt nunca avalia `error_if`. Por isso o exemplo de limiar troca as duas variáveis.

## D4. Onde ficam os testes: sinalizar na fonte, garantir nas camadas

**Escolha:**
- **Testes nos seeds** (`seeds/schema.yml`), severidade `warn`: descrevem os defeitos da fonte. É esperado que disparem.
- **Testes em staging, intermediate e marts**, severidade `error`: são o contrato dos modelos. Passam porque o staging filtra e deduplica via SQL.
- A chave `transaction_id` do seed é exceção: fica `error`, porque sem chave única nada a jusante faz sentido.

**Por quê:** é como o dbt separa "o dado que recebo está ruim" de "o modelo que eu entrego está errado". A leitura é direta: quando um teste da fonte (`warn`) aponta um defeito e o teste equivalente do staging (`error`) passa, o staging resolveu o problema no SQL, sem editar o CSV. Exemplo: `not_null_transactions_client_id` avisa sobre a T021, e `not_null_stg_transactions_client_id` passa porque a T021 foi filtrada. "Não limpar manualmente" significa não editar o CSV; filtrar no staging é pedido pelo requisito 1.

**Alternativa implementada:** testes da fonte bloqueantes, `--vars '{source_quality_severity: error}'`. Validado: os testes do seed falham (código 1) e os das camadas seguem passando.

## D5. Banco: DuckDB

| Opção | Status | Prós | Contras |
|---|---|---|---|
| **DuckDB** | Padrão | `pip install` e roda. Nada para configurar. | Não é banco de produção. |
| **Postgres** | Implementada e validada (`--target postgres`) | Mais realista | Exige Docker ou um Postgres. |
| BigQuery, Snowflake | Não implementada | É o que empresas usam | Exige credenciais que o avaliador não tem. |

**Por quê DuckDB:** rodar a partir do README sem ajuda pesa mais que realismo.

**Como a alternativa funciona:** o SQL usa as macros cross-database do dbt (`dbt.safe_cast`, `dbt.dateadd`, `dbt.type_float`), então o mesmo código roda nos dois bancos. `docker compose up -d`, `pip install -r requirements-postgres.txt` e `dbt build --target postgres`. Resultado esperado: `PASS=60 WARN=6 ERROR=0`, mesmas 98 transações e 6 posições negativas, incremental `delete+insert` funcionando.

Rodar no Postgres revelou um bug que o DuckDB escondia: o contrato declarava as colunas de texto como `varchar`, o Postgres criava a tabela com `character varying`, o SQL do modelo devolvia `text`, e a segunda execução incremental falhava por mudança de schema. A correção foi declarar `text` no contrato, que nos dois bancos é o tipo nativo de string.

## D6. Zero pacotes externos

**Escolha:** sem `packages.yml`. Os dois testes que viriam do `dbt_utils` são testes genéricos próprios em `tests/generic/`: `unique_combination` e `positive_value`.

**Por quê:** com `packages.yml`, é preciso rodar `dbt deps` antes. O avaliador disse que roda três comandos; se pular `dbt deps`, o `dbt run` quebra. Escrever os testes também conta para o bônus de macros.

## D7. Seeds carregados como texto

**Escolha:** `column_types` no `dbt_project.yml` força todas as colunas dos seeds para `varchar`.

**Por quê:** a camada bruta fica fiel ao arquivo, sem a inferência de tipos do dbt decidindo por nós, e a tipagem acontece onde o enunciado pede, no staging. Um valor estranho no CSV não derruba o `dbt seed`.

**Custo:** os testes no seed precisam fazer cast. O `positive_value` faz `dbt.safe_cast`, e um valor que não é número também conta como falha.

## D8. Limpeza em `stg_transactions`

- **Renomear:** só `operation` vira `operation_type`. As outras colunas já estão em snake_case; renomear sem ganho de clareza só atrapalha quem compara com a fonte.
- **Tipar com `dbt.safe_cast`:** um valor inválido (como `quantity = 'abc'`) vira nulo e é filtrado, em vez de derrubar o `dbt run`. No DuckDB isso exige um override: o `dbt.safe_cast` padrão do dbt-duckdb compila para um `cast` comum, que falha com erro de conversão. A macro `macros/safe_cast.sql` troca por `try_cast`. Validado trocando uma quantidade por `abc` numa cópia do CSV: o `dbt run` passa e a linha sai do staging. No Postgres não há `try_cast`, então lá um valor inválido ainda derruba o `dbt run`. Os dados do desafio não têm esse caso.
- **Padronizar:** `trim`, `upper` e string vazia vira nulo (macro `clean_string`).
- **Filtrar:** `client_id` nulo (T021), `quantity <= 0` (T037), `unit_price <= 0`, operação fora de BUY/SELL, data nula.
- **Deduplicar por `transaction_id`:** hoje não há duplicata por ID, mas é a chave e o custo é zero.

**Não implementado, de propósito:** reinterpretar T037 (BUY de -50) como venda de 50. Seria inventar o dado. É a mesma categoria de "corrigir o CSV".

## D9. T035 e T036 (a decisão mais discutível)

São idênticas em tudo menos no ID: C4 compra 120 ITUB4 a 28,50 em 27/03/2024.

**Escolha:** manter as duas, marcar com `is_possible_duplicate = true` e sinalizar com o teste `warn` `transactions_unique_content_except_id` no seed.

**Por quê:** duas ordens iguais no mesmo dia são possíveis (o cliente fracionou a ordem). Com dado financeiro, apagar uma transação com base num palpite é pior do que manter e sinalizar. A coluna deixa o consumidor decidir.

**Alternativa implementada:** `--vars '{dedup_transactions_by_content: true}'` mantém só a de menor ID. Validado: a fact cai de 98 para 97 linhas e a posição de C4 em ITUB4 cai de 240 para 120. Nenhuma das duas escolhas muda o resultado do teste singular.

## D10. Clientes duplicados (C1 e C6)

**Escolha:** uma linha por `client_id`, ficando o registro com menos campos nulos (macro `count_nulls`), com desempate por data de cadastro, nome e cidade para o resultado ser sempre o mesmo.

**Resultado validado:** de 27 para 25 linhas. C1 aparece duas vezes idêntico e fica com uma linha; C6 aparece com e sem cidade e fica com `city = Brasilia`, não com a cópia sem cidade. A ordem do `deduplicate` é: menos nulos (`count_nulls`), depois `client_created_date`, `client_name` e `city`.

**Alternativa não implementada:** pegar a primeira ou a última linha do arquivo. O CSV não tem coluna de ordem ou de atualização, então "primeira" dependeria da ordem de leitura do banco, que não é garantida.

**Relação com SCD (Slowly Changing Dimension):** manter uma única versão por cliente equivale a um **SCD tipo 1**: a dimensão guarda só o estado atual, e o histórico se perde. No C6 isso é seguro, porque os dois registros não são duas versões no tempo (um só não tem a cidade). Em produção, se um atributo realmente mudasse (o cliente se mudou de cidade, por exemplo) e o histórico importasse, eu usaria **SCD tipo 2**: uma nova linha por versão, com `valid_from` e `valid_to`. No dbt, isso se faz com **snapshots** (`dbt snapshot`) sobre a tabela de clientes da origem, com estratégia `timestamp` (quando houver uma coluna de atualização) ou `check` (comparando as colunas). A `dim_clients` passaria a ler do snapshot, e a fact faria o join pela versão vigente na data da transação.

**Por que não implementei:** o CSV é uma foto única, sem coluna de atualização nem cargas em datas diferentes, então um snapshot teria uma só versão por cliente e não mostraria nada.

**Cenário: como ficaria o SCD tipo 2.** Suponha que o `clients.csv` viesse com uma coluna `updated_at` e várias versões por cliente, por exemplo o C6 se mudando de Brasília para São Paulo em 2024-06-16. A `dim_clients` passaria a ter uma linha por versão:

| client_sk | client_id | client_name | city | valid_from | valid_to | is_current |
|---|---|---|---|---|---|---|
| `a1f…` | C6 | Felipe Nunes | Brasilia | 2023-04-30 | 2024-06-16 | false |
| `9c4…` | C6 | Felipe Nunes | Sao Paulo | 2024-06-16 | null | true |

No dbt, seriam três peças:

1. **Snapshot** sobre a origem dos clientes, com estratégia `timestamp`:

   ```yaml
   # snapshots/clients_snapshot.yml
   snapshots:
     - name: clients_snapshot
       relation: source('crm', 'clients')
       config:
         unique_key: client_id
         strategy: timestamp
         updated_at: updated_at
   ```

   A cada `dbt snapshot`, uma versão que mudou ganha linha nova. O dbt preenche `dbt_valid_from` e `dbt_valid_to` (nulo na versão vigente).

2. **`dim_clients` lendo do snapshot**, com uma surrogate key por versão (D21) e o intervalo renomeado:

   ```sql
   select
       {{ dbt_utils.generate_surrogate_key(['client_id', 'dbt_valid_from']) }} as client_sk,
       client_id, client_name, city, state,
       dbt_valid_from          as valid_from,
       dbt_valid_to            as valid_to,
       dbt_valid_to is null    as is_current
   from {{ ref('clients_snapshot') }}
   ```

3. **A fato aponta para a versão vigente na data da transação**, guardando `client_sk` em vez de só `client_id`:

   ```sql
   left join {{ ref('dim_clients') }} as dim
       on  t.client_id = dim.client_id
       and t.transaction_date >= dim.valid_from
       and (t.transaction_date < dim.valid_to or dim.valid_to is null)
   ```

   O intervalo é fechado no início e aberto no fim, porque o dbt grava o `valid_to` de uma versão igual ao `valid_from` da seguinte. Assim, uma compra do C6 em 2024-01-10 fica ligada à versão de Brasília e uma de 2024-07-01 à de São Paulo, e uma análise por cidade mostra onde o cliente estava quando operou.

**O que mudaria nos testes:** `unique` passaria de `client_id` para `client_sk`, mais um teste de que cada `client_id` tem exatamente uma linha com `is_current = true` e de que os intervalos não se sobrepõem. O `relationships` da fato passaria a apontar para `client_sk`.

## D11. Não filtrar posições negativas no mart

**Escolha:** o mart mostra todas as posições, inclusive zeradas e negativas. A coluna `position_status` (`open`, `closed`, `negative`) deixa quem consome decidir.

**Por quê:** o teste singular precisa ver as negativas. Filtrá-las faz o teste passar escondendo o problema, que é justamente o "limpar os dados" que o enunciado proíbe.

**Alternativa rejeitada, implementada só para demonstrar:** `--vars '{portfolio_hide_negative_positions: true}'`. Validado: com ela, o teste singular passa até em modo estrito, porque não há mais nada para ver. É a demonstração de por que essa opção é ruim.

## D12. O que `net_amount` significa

**Escolha:** `net_amount = total comprado em R$ - total vendido em R$`. É a **posição líquida em valor financeiro** (BUY − SELL), como o enunciado chama, e não volume financeiro, valor de mercado nem custo da posição. Está escrito assim na documentação da coluna.

**Consequência:** o teste singular olha `net_quantity`, não `net_amount`. Valor negativo com quantidade positiva é legítimo (o cliente vendeu mais em reais do que comprou) e não indica lucro nem prejuízo. Hoje isso não ocorre nos dados, mas é a regra correta.

## D13. `fact_transactions` incremental (bônus 6)

**Escolha:**

```sql
where transaction_date >= max(transaction_date) - 3 dias
```

com `unique_key = transaction_id`, estratégia `delete+insert` e `on_schema_change = fail`.

**Por quê:**
- **Janela de N dias.** Uma transação atrasada chega com data igual ou anterior à maior já carregada. Reprocessar os últimos N dias a pega, e é a janela que protege, não só o operador. O `>=` inclui por inteiro o dia da borda (maior data menos N). Validado: uma linha nova (T999) com a data máxima já carregada entra na execução incremental.
- **`unique_key`** torna o reprocessamento da janela idempotente. Validado: a segunda execução mantém 98 linhas.
- **`delete+insert`** é estável no DuckDB e fácil de explicar.
- **`on_schema_change = fail`:** mudança de schema tem que ser decisão consciente (`--full-refresh`).

**Estratégia fixa:** `delete+insert`, sem alternativa por variável. `merge` e `append` foram avaliadas e removidas para simplificar o modelo.

O tamanho da janela também é variável: `fact_lookback_days` (padrão 3).

**Limitação:** a janela por data de transação não pega correção retroativa de uma transação antiga. Em produção eu usaria uma coluna `loaded_at` ou `updated_at` da fonte.

## D14. Macros (bônus 7)

Só lógica que realmente se repete:
- `clean_string(col)`: `nullif(trim(col), '')`. Usada nos dois modelos de staging.
- `deduplicate(relation, partition_by, order_by)`: `row_number()` e filtro. Usada nos dois modelos de staging.
- `count_nulls(columns)`: soma de nulos numa lista de colunas, para escolher o registro mais completo. Usada só no `stg_clients`.
- `duckdb__safe_cast`: override do `dbt.safe_cast` com `try_cast`, para um valor inválido virar nulo no DuckDB (D8).
- Testes genéricos `positive_value`, usado em seeds, staging, intermediate e marts, e `unique_combination`, usado nos seeds para sinalizar T035/T036.

**Não virou macro:** `signed_quantity`. Seria usada num lugar só, e SQL direto é mais legível.

## D15. `profiles.yml` na raiz

O dbt procura o profile no diretório atual antes de `~/.dbt`. Com o arquivo na raiz e o banco num caminho relativo (`cdv.duckdb`), o avaliador não configura nada. O caminho pode ser trocado com `DBT_DUCKDB_PATH`, para não mexer no banco do dia a dia.

## D16. Contratos nos marts

**Escolha:** `contract: {enforced: true}` em `fact_transactions`, `dim_clients` e `mart_client_portfolio`, com tipo declarado para toda coluna.

**Por quê:** os marts são a interface com quem consome. Com contrato, uma mudança de tipo quebra o `dbt run` em vez de chegar silenciosamente ao dashboard. Para isso, as somas de quantidade viraram `bigint` explícito (o DuckDB devolveria `hugeint`).

## D18. Doc blocks

Descrições repetidas (`client_id`, `transaction_id`, `net_amount` e outras) estão em `models/docs.md` e são referenciadas com `{{ doc('...') }}`. Toda coluna de todo modelo e seed tem descrição (requisito 5). `dbt docs generate` roda sem avisos.

## D19. CI no GitHub Actions

Dois jobs num runner limpo:
- **DuckDB:** os três comandos do README, a confirmação de que o modo estrito falha e `dbt docs generate`.
- **Postgres:** `dbt build --target postgres` contra um Postgres 16 e uma segunda execução incremental.

**Por quê:** é a prova pública de que o projeto roda do zero, sem "funciona na minha máquina".

## D20. `seed` + `run` + `test` ou `dbt build`

**Escolha:** o README usa os três comandos, porque é o que o avaliador disse que vai rodar.

**Alternativa validada:** `dbt build` roda tudo em ordem de dependência e também sai com código 0. Fica como dica no README.

## D21. Chave da dimensão: `client_id` original

**Escolha:** `dim_clients` usa o `client_id` da origem como chave, e a fact faz o join por ele.

**Por quê:** com uma versão por cliente (D10) e um único sistema de origem, o ID natural é único e estável, e mantém o projeto sem pacotes externos (D6).

**Em produção:** eu usaria uma **surrogate key**, uma chave gerada pelo data warehouse (no dbt, com `dbt_utils.generate_surrogate_key`, a partir do `client_id` e, no SCD tipo 2, do `valid_from`). Ela protege contra mudanças de ID na origem, permite juntar clientes de sistemas diferentes e é necessária quando a dimensão guarda várias versões do mesmo cliente.

## D22. Marts leem da fato (estilo Kimball)

**Escolha:** `mart_client_portfolio` e as métricas de atividade da `dim_clients` (primeira e última transação, total) leem da `fact_transactions`, não do `int_transactions`. O cadastro da `dim_clients` continua vindo do `stg_clients`.

**Por quê:** é o desenho dimensional clássico: a fato é a fonte única das transações publicadas, e tudo que agrega transações parte dela. O portfólio fica sempre consistente com a fato que o consumidor também consulta, e a linhagem fica mais simples de explicar. Nenhuma métrica foi perdida, porque a fato já tem todas as colunas de que os dois modelos precisam. Um `ref()` a um modelo incremental lê a tabela inteira (as 98 linhas), não só a janela de reprocessamento, então os números não mudaram: portfólio com 55 linhas, `dim_clients` com 25 e `dbt test` com `PASS=52 WARN=7`.

**Custo:** o portfólio herda qualquer desvio do incremental. Uma correção retroativa fora da janela (limitação do D13) também não chegaria ao portfólio até um `--full-refresh`.

**Alternativa não implementada:** os marts lerem direto do `int_transactions`, como irmãos da fato. O portfólio seria sempre recalculado da fonte completa e não herdaria limitações do incremental, ao custo de duas linhas de cálculo paralelas que podem divergir.

## Problemas nos dados e onde cada um aparece

| Registro | Problema | Teste que sinaliza (warn) | Tratamento |
|---|---|---|---|
| T021 | `client_id` vazio | `not_null_transactions_client_id` | Filtrado no staging (D8) |
| T037 | BUY com quantidade -50 | `positive_value_transactions_quantity` | Filtrado no staging (D8) |
| T035/T036 | Idênticas exceto ID | `transactions_unique_content_except_id` | Mantidas e marcadas (D9) |
| C1 | Linha duplicada idêntica | `unique_clients_client_id` | Deduplicado (D10) |
| C6 | Duplicada, cópia sem cidade | `unique_clients_client_id`, `not_null_clients_city` | Fica a versão com cidade (D10) |
| C1, C3, C5, C6, C7, C8 | Posição final negativa em 6 pares | `assert_no_negative_position` | Mantidas e sinalizadas (D3, D11) |
| C11 a C25 | Clientes sem transação | Nenhum: não é erro | Aparecem na dimensão com `has_transactions = false` |
