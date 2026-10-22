# Decisões do projeto

Este documento explica cada decisão tomada no projeto: o que foi feito, por que, quais alternativas existiam e onde a decisão aparece no código. O README diz **como rodar**; este documento diz **por que o projeto é assim**.

## Como ler

As decisões estão agrupadas por tema, na ordem em que o dado percorre o projeto: primeiro como ele roda, depois os testes, e então seeds, staging, intermediate e marts. Cada uma tem um código (D1, D2…) e segue o mesmo formato:

- **O que foi feito**: a escolha, de forma concreta.
- **Por quê**: o motivo, quase sempre ligado a uma frase do enunciado.
- **Alternativas**: o que mais foi considerado. Quando faz sentido, a alternativa está implementada e é ligada por uma variável do dbt (`--vars`), sem editar código.
- **Onde está**: os arquivos em que a decisão aparece.

Versões usadas na validação: dbt-core 1.12.5 e dbt-duckdb 1.11.0. A alternativa Postgres foi validada com dbt-postgres 1.11.0 e Postgres 16.

## Resultado esperado

Com os valores padrão, os três comandos terminam sem erro (código de saída 0):

```
dbt seed   →  PASS=2
dbt run    →  PASS=6
dbt test   →  PASS=52 WARN=6 ERROR=0
```

Os 6 avisos (`WARN`) são os defeitos plantados nos dados, encontrados pelos testes. A tabela no fim deste documento mostra cada um.

## Sumário

| Código | Decisão | Padrão | Como mudar |
|---|---|---|---|
| **Execução e arquitetura** | | | |
| D1 | Banco | DuckDB, arquivo local | `--target postgres` |
| D2 | Versões | dbt-core 1.12.5 e dbt-duckdb 1.11.0, fixas | |
| D3 | Profile | `profiles.yml` na raiz do projeto | `DBT_DUCKDB_PATH=outro.duckdb` |
| D4 | Pacotes externos | nenhum, sem `dbt deps` | |
| D5 | Camadas e materializações | staging e intermediate `view`, marts `table`, fato `incremental` | |
| D6 | Comandos | `dbt seed`, `dbt run`, `dbt test` | `dbt build` |
| D7 | CI | GitHub Actions com DuckDB e Postgres | |
| **Testes** | | | |
| D8 | Severidade do teste singular (a decisão central) | `warn` com `store_failures` | `--vars '{negative_position_severity: error}'` |
| D9 | Severidade por camada | fonte `warn`, modelos `error` | `--vars '{source_quality_severity: error}'` |
| D10 | Testes genéricos próprios | `positive_value` e `unique_combination` | |
| D11 | Destino dos `relationships` | sempre a camada limpa ou a dimensão | |
| **Seeds e staging** | | | |
| D12 | Tipos dos seeds | tudo texto, tipagem no staging | |
| D13 | Limpeza das transações | filtrar inválidos no staging | |
| D14 | Clientes duplicados | fica o registro mais completo (SCD tipo 1) | |
| **Intermediate** | | | |
| D15 | Transações T035 e T036 | mantidas e sinalizadas | `--vars '{dedup_transactions_by_content: true}'` |
| D16 | Sinal da operação | regra de compra e venda definida uma vez | |
| **Marts** | | | |
| D17 | Fato incremental | `delete+insert`, janela de 3 dias | `--vars '{fact_lookback_days: 7}'` |
| D18 | Colunas da fato | 11 colunas, sem atributos do cliente | |
| D19 | De onde os marts leem | da fato (estilo Kimball) | |
| D20 | Dimensão de clientes | todos os clientes, chave `client_id` | |
| D21 | Métricas do portfólio | posição líquida em quantidade e em valor | |
| D22 | Posições negativas | classificadas, não filtradas | `--vars '{portfolio_hide_negative_positions: true}'` |
| D23 | Contratos | aplicados nos três marts | |
| **Macros e documentação** | | | |
| D24 | Macros | só lógica que se repete | |
| D25 | Descrições das colunas | doc blocks reutilizados | |

---

# Execução e arquitetura

## D1. Banco: DuckDB

**O que foi feito.** O projeto usa DuckDB por padrão. O banco é um arquivo local, `cdv.duckdb`, criado na primeira execução.

**Por quê.** O enunciado diz que, se o projeto não rodar a partir do README sem ajuda externa, a entrega não é avaliada. Com DuckDB, basta um `pip install`: não há servidor, Docker nem credenciais. Rodar sem ajuda pesa mais do que usar um banco de produção.

**Alternativas.**

| Opção | Situação | Prós | Contras |
|---|---|---|---|
| **DuckDB** | Padrão | Instala com `pip` e roda | Não é um banco de produção |
| **Postgres** | Implementada e validada (`--target postgres`) | Mais próximo de produção | Exige Docker ou um Postgres rodando |
| BigQuery, Snowflake | Não implementada | É o que as empresas usam | Exige credenciais que o avaliador não tem |

**Como a alternativa funciona.** O SQL usa as macros do dbt que funcionam em vários bancos (`dbt.safe_cast`, `dbt.dateadd`, `dbt.type_float`), então o mesmo código roda nos dois. Para usar o Postgres: `docker compose up -d`, `pip install -r requirements-postgres.txt` e `dbt build --target postgres`. Resultado esperado: `PASS=60 WARN=6 ERROR=0`, com as mesmas 98 transações e as mesmas 6 posições negativas.

Rodar no Postgres revelou um bug que o DuckDB escondia. O contrato declarava as colunas de texto como `varchar`, o Postgres criava a tabela com `character varying`, o SQL do modelo devolvia `text`, e a segunda execução incremental falhava por mudança de schema. A correção foi declarar `text` no contrato, que é o tipo nativo de texto nos dois bancos.

**Onde está.** `profiles.yml` (targets `dev` e `postgres`), `docker-compose.yml`, `requirements-postgres.txt`.

## D2. Versões fixas

**O que foi feito.** O `requirements.txt` fixa `dbt-core==1.12.5` e `dbt-duckdb==1.11.0`. O projeto funciona com Python 3.10 a 3.13.

**Por quê.** Uma versão nova do dbt pode mudar a sintaxe. O dbt 1.10, por exemplo, mudou o formato dos testes genéricos para `arguments:`. Fixar as versões elimina essa variável: quem instala hoje ou daqui a um ano recebe exatamente o que foi testado.

**Onde está.** `requirements.txt`.

## D3. `profiles.yml` na raiz do projeto

**O que foi feito.** O `profiles.yml` fica na raiz do repositório, e não em `~/.dbt`. O caminho do banco é relativo (`cdv.duckdb`) e pode ser trocado pela variável de ambiente `DBT_DUCKDB_PATH`.

**Por quê.** O dbt procura o `profiles.yml` no diretório atual antes de procurar em `~/.dbt`. Com o arquivo na raiz, quem roda o projeto não configura nada. A variável de ambiente permite usar outro banco, por exemplo para testes, sem mexer no banco do dia a dia.

**Onde está.** `profiles.yml`.

## D4. Nenhum pacote externo

**O que foi feito.** O projeto não tem `packages.yml`. Os dois testes que normalmente viriam do pacote `dbt_utils` foram escritos no próprio projeto (D10).

**Por quê.** Com um `packages.yml`, é preciso rodar `dbt deps` antes de qualquer outro comando. O enunciado diz que a avaliação roda três comandos (`dbt seed`, `dbt run` e `dbt test`), e o `dbt deps` não está entre eles. Se ele fosse necessário e alguém o pulasse, o `dbt run` quebraria.

**Onde está.** `tests/generic/`.

## D5. Camadas e materializações

**O que foi feito.** O projeto tem as três camadas do enunciado, cada uma com uma responsabilidade:

| Camada | Modelos | Materialização | Responsabilidade |
|---|---|---|---|
| staging | `stg_transactions`, `stg_clients` | `view` | Tipar, padronizar, filtrar e deduplicar o dado bruto |
| intermediate | `int_transactions` | `view` | Juntar transações e clientes e aplicar as regras de negócio |
| marts | `fact_transactions` | `incremental` | Publicar as transações (D17) |
| marts | `dim_clients`, `mart_client_portfolio` | `table` | Publicar a dimensão e o portfólio |

**Por quê.** As views de staging e intermediate são baratas e sempre refletem o dado mais recente. Os marts são o que o consumidor lê, então viram tabelas, que são rápidas de consultar. A fato é incremental porque é o bônus 6 do enunciado.

**Alternativa não implementada.** O intermediate como `ephemeral`, que o dbt injeta como CTE em quem o usa, sem criar nada no banco. O problema é que um modelo ephemeral não pode ser testado nem consultado, então os testes do `int_transactions` deixariam de existir. Num projeto deste tamanho, perde-se mais do que se ganha.

**Onde está.** `dbt_project.yml` (seção `models`) e o `config` da `fact_transactions`.

## D6. Três comandos ou `dbt build`

**O que foi feito.** O README instrui a rodar `dbt seed`, `dbt run` e `dbt test`, nessa ordem.

**Por quê.** São os três comandos que o enunciado diz que serão usados na avaliação.

**Alternativa validada.** `dbt build` roda seeds, modelos e testes em ordem de dependência e também termina sem erro. O README menciona como um atalho.

## D7. CI no GitHub Actions

**O que foi feito.** Um workflow roda em todo push e em todo pull request, com dois jobs num ambiente limpo:

- **DuckDB:** instala o `requirements.txt`, roda os três comandos do README, confirma que o teste singular reprova no modo estrito e roda `dbt docs generate`.
- **Postgres:** sobe um Postgres 16, roda `dbt build --target postgres` e uma segunda execução incremental da fato.

**Por quê.** É a prova pública de que o projeto roda do zero, seguindo o README, e não só na minha máquina.

**Onde está.** `.github/workflows/dbt.yml`.

---

# Testes

## D8. Severidade do teste singular (a decisão central)

**O problema.** O enunciado pede duas coisas que, ao pé da letra, se contradizem. Ele diz que "tudo tem que passar" no `dbt test` e que "o teste singular deve detectar o problema nos dados". No dbt, um teste que encontra linhas falha, e o teste singular encontra seis.

**O que foi feito.** O teste `assert_no_negative_position` tem severidade `warn` por padrão, definida pela variável `negative_position_severity`. Os testes do projeto têm `store_failures: true`, então as linhas encontradas ficam gravadas no banco:

```
WARN 6 assert_no_negative_position
Done. PASS=52 WARN=6 ERROR=0     (código de saída 0)
```

As seis linhas ficam na tabela `main_dbt_test__audit.assert_no_negative_position`.

**Por quê.**

1. Atende as duas frases do enunciado: o teste detecta o problema (mostra o aviso, conta as linhas e as grava) e o comando passa.
2. É o mecanismo que o dbt oferece para isso. `error` quer dizer "o contrato do meu modelo quebrou". `warn` quer dizer "existe um problema conhecido no dado, e alguém precisa vê-lo".
3. Protege o critério eliminatório: o `dbt test` termina com código 0.
4. Tornar o teste bloqueante é questão de passar uma variável, sem editar código.

**Alternativas.**

| Alternativa | Situação | Como ativar |
|---|---|---|
| Severidade `error` | Implementada e validada: o `dbt test` termina com código 1 | `dbt test --vars '{negative_position_severity: error}'` |
| Limite de linhas (avisa até N, falha acima) | Implementada e validada | `dbt test --vars '{negative_position_severity: error, negative_position_error_if: ">10"}'` |
| Filtrar as negativas no portfólio | Implementada só para mostrar o efeito (D22) | `--vars '{portfolio_hide_negative_positions: true}'` |
| Corrigir os CSVs | Não implementada: o enunciado proíbe | |

O limite de linhas só funciona com severidade `error`. Com `warn`, o dbt nunca avalia o `error_if`. Por isso o exemplo troca as duas variáveis.

**Por que o teste olha a quantidade.** O teste usa `net_quantity < 0`, e não o `net_amount`. A pergunta é se o cliente vendeu mais ações do que tinha, e isso é uma questão de quantidade. O `net_amount` negativo com quantidade positiva é uma situação legítima (D21).

**O que ele encontra.** Seis posições negativas: C1 em BBDC4 (−50), C3 em WEGE3 (−30), C5 em BBDC4 (−400), C6 em ITUB4 (−50), C7 em WEGE3 (−60) e C8 em VALE3 (−30). Só o caso do C5, que compra 200 e vende 600, é o mais óbvio. Os outros cinco são vendas de um ativo que o cliente nunca comprou.

**Onde está.** `tests/assert_no_negative_position.sql`, `dbt_project.yml` (variáveis e `store_failures`).

## D9. Severidade por camada: sinalizar na fonte, garantir nas camadas

**O que foi feito.**

- **Testes nos seeds** (`seeds/schema.yml`) têm severidade `warn`, definida pela variável `source_quality_severity`. Eles descrevem os defeitos do dado recebido, e é esperado que disparem.
- **Testes em staging, intermediate e marts** têm severidade `error`. São o contrato dos modelos e passam porque o staging filtra e deduplica no SQL.
- A chave `transaction_id` do seed é a exceção: tem `unique` e `not_null` com severidade `error`, porque sem uma chave única nada que vem depois faz sentido.

**Por quê.** É a forma de separar "o dado que eu recebo está ruim" de "o modelo que eu entrego está errado". A leitura fica direta. Quando um teste da fonte avisa e o mesmo teste no staging passa, isso prova que o staging resolveu o problema no SQL, sem editar o CSV. Por exemplo: `not_null_transactions_client_id` avisa sobre a T021, e `not_null_stg_transactions_client_id` passa, porque a T021 foi filtrada.

O enunciado pede para não limpar os dados manualmente. Isso significa não editar o CSV. Filtrar registros inválidos no staging é justamente o que o requisito 1 pede.

**Alternativa implementada.** Testes da fonte bloqueantes, com `--vars '{source_quality_severity: error}'`. Validado: os testes do seed falham (código 1) e os das camadas continuam passando.

**Onde está.** `seeds/schema.yml` e os `schema.yml` de `models/`.

## D10. Testes genéricos escritos no projeto

**O que foi feito.** Dois testes genéricos em `tests/generic/`, no lugar dos equivalentes do `dbt_utils` (D4):

- **`positive_value`** acusa todo valor que não é estritamente positivo, ou seja, zero também falha. Como os seeds são texto (D12), o teste converte a coluna para número com `dbt.safe_cast`. A comparação fica dentro de `coalesce(..., true)`: se o cast falhar e devolver nulo, a linha conta como violação, então um valor não numérico também é pego. Valores nulos ficam de fora, porque quem cuida deles é o `not_null`. É usado em `quantity` e `unit_price` nos seeds, no staging e na fato, e em `gross_amount` no intermediate. Nos seeds, pega a T037, com quantidade −50.
- **`unique_combination`** agrupa a tabela pelas colunas passadas e devolve as combinações que aparecem em mais de uma linha. É usado no seed de transações, com o nome `transactions_unique_content_except_id`, sobre seis colunas: cliente, ativo, operação, quantidade, preço e data. O `transaction_id` fica de fora de propósito, porque com o ID nenhuma linha seria igual a outra. Assim o teste compara o conteúdo da transação e pega a T035 e a T036, que o `unique` do ID não pegaria.

**Por quê.** Os dois cobrem regras que os testes nativos do dbt (`not_null`, `unique`, `accepted_values`, `relationships`) não cobrem, e escrevê-los evita depender de pacote.

**Onde está.** `tests/generic/positive_value.sql`, `tests/generic/unique_combination.sql`, `seeds/schema.yml`.

## D11. Para onde apontam os `relationships`

**O que foi feito.** Cada teste `relationships` aponta para a versão do cadastro que pertence à mesma camada:

| Teste em | Aponta para | Severidade |
|---|---|---|
| seed `transactions.client_id` | seed `clients.client_id` | `warn` |
| `stg_transactions.client_id` | `stg_clients.client_id` | `error` |
| `fact_transactions.client_id` | `dim_clients.client_id` | `error` |
| `mart_client_portfolio.client_id` | `dim_clients.client_id` | `error` |

**Por quê.** A camada limpa referencia a camada limpa: o `stg_clients` é o cadastro deduplicado, então é ele que vale como referência para o staging. Nos marts, a fato e o portfólio apontam para a dimensão, como num modelo estrela.

O `relationships` ignora valores nulos. Por isso a T021, que não tem cliente, não é acusada por ele, e sim pelo `not_null`.

**Onde está.** Os `schema.yml` de `seeds/` e de `models/`.

---

# Seeds e staging

## D12. Seeds carregados como texto

**O que foi feito.** O `dbt_project.yml` define `column_types` para que todas as colunas dos dois seeds sejam carregadas como `varchar`. Os tipos ficam definidos por seed, porque o dbt avisa quando uma coluna listada não existe no CSV.

**Por quê.** A camada bruta fica fiel ao arquivo, sem a inferência de tipos do dbt decidindo por conta própria. Um valor estranho no CSV não derruba o `dbt seed`. E a tipagem acontece onde o enunciado pede, no staging.

**Custo.** Os testes nos seeds precisam fazer cast antes de comparar números. É por isso que o `positive_value` converte a coluna (D10).

**Onde está.** `dbt_project.yml` (seção `seeds`).

## D13. Limpeza das transações no staging

**O que foi feito.** O `stg_transactions` tem quatro CTEs:

1. **`source`**: lê o seed bruto.
2. **`renamed`**: renomeia, padroniza e tipa.
   - A única coluna renomeada é `operation`, que vira `operation_type`, porque "operation" sozinho é vago. As outras já estão em snake_case, e renomear sem ganho de clareza só dificulta comparar com a fonte.
   - A macro `clean_string` tira os espaços das pontas e transforma texto vazio em nulo. O `upper` padroniza os códigos em maiúsculas, para o join com os clientes não falhar por diferença de caixa.
   - O `dbt.safe_cast` tipa cada coluna: inteiro para a quantidade, `decimal(18,4)` para o preço e data para a data. Um valor que não converte vira nulo, em vez de derrubar o `dbt run`. No DuckDB, isso depende de um override com `try_cast` (D24).
3. **`valid`**: remove as linhas sem ID, sem cliente ou sem ativo, com operação diferente de `BUY` e `SELL`, com quantidade ou preço não positivos, ou com data inválida. Como o filtro vem depois do cast, um valor que não converteu também sai aqui. Saem a T021 (sem cliente) e a T037 (quantidade −50), e sobram 98 linhas.
4. **`deduplicated`**: mantém uma linha por `transaction_id`, a de data mais antiga, com o cliente como desempate. Hoje não há ID repetido, então nada é removido. Mas é a chave da tabela, e a defesa não custa nada.

**Por quê.** O requisito 1 pede renomeação, tipos corretos e filtro de registros inválidos. Fazer isso em SQL reproduzível, e não editando o CSV, mantém a fonte intacta e torna a limpeza auditável.

**O que não foi feito, de propósito.** A T037 é uma compra de −50. Reinterpretá-la como uma venda de 50 seria inventar o dado, a mesma categoria de "corrigir o CSV".

**Onde está.** `models/staging/stg_transactions.sql`.

## D14. Clientes duplicados (C1 e C6)

**O que foi feito.** O `stg_clients` tem a mesma estrutura de quatro CTEs. Ele renomeia `name` para `client_name` e `created_at` para `client_created_date`, porque é uma data e não um timestamp. A diferença está na deduplicação: fica uma linha por `client_id`, a do registro com menos campos nulos, contados pela macro `count_nulls`. Em caso de empate, a ordem é por data de cadastro, nome e cidade, para o resultado ser sempre o mesmo.

**Resultado.** De 27 para 25 linhas. O C1 aparece duas vezes, idêntico, e fica com uma linha. O C6 aparece com e sem cidade, e fica a versão com `city = Brasilia`.

**Por quê.** Entre duas versões do mesmo cliente, a mais completa é a que carrega mais informação.

**Alternativa não implementada.** Pegar a primeira ou a última linha do arquivo. O CSV não tem coluna de ordem nem de atualização, então "a primeira" dependeria da ordem em que o banco lê as linhas, que não é garantida.

**Relação com SCD (Slowly Changing Dimension).** Manter uma única versão por cliente equivale a um **SCD tipo 1**: a dimensão guarda só o estado atual, e o histórico se perde. No C6 isso é seguro, porque os dois registros não são duas versões no tempo: um deles só não tem a cidade.

Em produção, se um atributo realmente mudasse (o cliente se mudou de cidade, por exemplo) e o histórico importasse, o caminho seria um **SCD tipo 2**: uma linha por versão, com `valid_from` e `valid_to`. No dbt, isso se faz com **snapshots** (`dbt snapshot`) sobre a tabela de clientes da origem. A estratégia seria `timestamp`, quando houver uma coluna de atualização, ou `check`, comparando as colunas. A `dim_clients` passaria a ler do snapshot, e a fato faria o join com a versão vigente na data de cada transação.

**Por que não foi implementado.** O CSV é uma foto única, sem coluna de atualização nem cargas em datas diferentes. Um snapshot teria uma só versão por cliente e não mostraria nada.

**Cenário: como ficaria o SCD tipo 2.** Suponha que o `clients.csv` viesse com uma coluna `updated_at` e várias versões por cliente, por exemplo o C6 se mudando de Brasília para São Paulo em 2024-06-16. A `dim_clients` passaria a ter uma linha por versão:

| client_sk | client_id | client_name | city | valid_from | valid_to | is_current |
|---|---|---|---|---|---|---|
| `a1f…` | C6 | Felipe Nunes | Brasilia | 2023-04-30 | 2024-06-16 | false |
| `9c4…` | C6 | Felipe Nunes | Sao Paulo | 2024-06-16 | null | true |

No dbt, seriam três peças:

1. **Um snapshot** sobre a origem dos clientes, com estratégia `timestamp`:

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

   A cada `dbt snapshot`, uma versão que mudou ganha uma linha nova. O dbt preenche `dbt_valid_from` e `dbt_valid_to`, que fica nulo na versão vigente.

2. **A `dim_clients` lendo do snapshot**, com uma surrogate key por versão (D20) e o intervalo renomeado:

   ```sql
   select
       {{ dbt_utils.generate_surrogate_key(['client_id', 'dbt_valid_from']) }} as client_sk,
       client_id, client_name, city, state,
       dbt_valid_from          as valid_from,
       dbt_valid_to            as valid_to,
       dbt_valid_to is null    as is_current
   from {{ ref('clients_snapshot') }}
   ```

3. **A fato apontando para a versão vigente na data da transação**, guardando `client_sk` em vez de só `client_id`:

   ```sql
   left join {{ ref('dim_clients') }} as dim
       on  t.client_id = dim.client_id
       and t.transaction_date >= dim.valid_from
       and (t.transaction_date < dim.valid_to or dim.valid_to is null)
   ```

   O intervalo é fechado no início e aberto no fim, porque o dbt grava o `valid_to` de uma versão igual ao `valid_from` da seguinte. Assim, uma compra do C6 em 2024-01-10 fica ligada à versão de Brasília e uma de 2024-07-01 à de São Paulo, e uma análise por cidade mostra onde o cliente estava quando operou.

**O que mudaria nos testes.** O `unique` passaria de `client_id` para `client_sk`. Entrariam testes de que cada `client_id` tem exatamente uma linha com `is_current = true` e de que os intervalos não se sobrepõem. O `relationships` da fato passaria a apontar para `client_sk`.

**Onde está.** `models/staging/stg_clients.sql`, `macros/count_nulls.sql`, `macros/deduplicate.sql`.

---

# Intermediate

## D15. Transações T035 e T036: mantidas e sinalizadas

**O caso.** As duas são idênticas em tudo menos no ID: o C4 compra 120 ITUB4 a R$ 28,50 em 27/03/2024. É a decisão mais discutível do projeto.

**O que foi feito.** As duas são mantidas e recebem `is_possible_duplicate = true`. No seed, o teste `transactions_unique_content_except_id` as sinaliza com `warn` (D10).

No `int_transactions`, isso acontece em duas CTEs:

- **`flagged`**: usa `count(*) over` para contar quantas transações têm o mesmo conteúdo (cliente, ativo, operação, quantidade, preço e data) e `row_number()` para ordená-las por `transaction_id`.
- **`kept`**: por padrão, mantém todas. Com a variável ligada, fica só a de menor ID.

**Por quê.** Duas ordens iguais no mesmo dia são possíveis: o cliente pode ter dividido uma ordem em duas. Com dado financeiro, apagar uma transação com base num palpite é pior do que mantê-la e sinalizar. A coluna deixa quem consome decidir.

**Alternativa implementada.** `--vars '{dedup_transactions_by_content: true}'` mantém só a de menor ID. Validado: a fato cai de 98 para 97 linhas, e a posição do C4 em ITUB4 cai de 240 para 120. Nenhuma das duas escolhas muda o resultado do teste singular. Como a fato é incremental, a troca exige `dbt run --full-refresh`.

**Onde está.** `models/intermediate/int_transactions.sql`.

## D16. Sinal da operação

**O que foi feito.** Na CTE `enriched`, o `int_transactions` junta as transações com os clientes, para trazer nome e estado, e cria três colunas de valor:

- **`signed_quantity`**: a quantidade com o sinal da operação, positiva na compra e negativa na venda.

  ```sql
  case operation_type
      when 'BUY'  then quantity
      when 'SELL' then -quantity
  end
  ```

- **`gross_amount`**: quantidade vezes preço, o valor da operação em reais, sempre positivo.
- **`signed_amount`**: o `gross_amount` com o sinal da operação, positivo na compra e negativo na venda. É calculado no select final, como `sign(signed_quantity) * gross_amount`.

**Por quê.**

- **A regra de compra e venda é definida uma vez só**, no `signed_quantity`. As outras colunas derivam dela. Assim o `net_quantity` e o `net_amount` do portfólio viram somas simples, sem precisar de `case` para saber quando subtrair.
- **Os dois casos do `case` são explícitos, sem `else`.** Com um `else`, qualquer valor que não fosse `BUY` (um `TRANSFER`, um erro de digitação) viraria venda sem ninguém perceber. Sem o `else`, um valor desconhecido vira nulo, e o teste `not_null` do `signed_quantity` acusa. Hoje isso não acontece, porque o staging só deixa passar `BUY` e `SELL`.
- **O `signed_amount` fica numa etapa separada** porque depende do `signed_quantity`, que é um alias criado no mesmo `SELECT`. O DuckDB aceita usar um alias no mesmo `SELECT`, mas o Postgres não, e o projeto roda nos dois (D1). O otimizador junta as duas etapas num plano só, então não há custo de desempenho.
- **O `gross_amount` existe ao lado do `signed_amount`** pela mesma lógica do par `quantity` e `signed_quantity`: quem consome encontra o valor com e sem sinal. Ele alimenta os totais comprados e vendidos do portfólio.

**O que não virou macro.** O cálculo do `signed_quantity` aparece num lugar só, e SQL direto é mais legível (D24).

**Testes.** O `schema.yml` do intermediate repete só os testes da chave (`unique` e `not_null` no `transaction_id`, `not_null` no `client_id`) e testa o que nasce aqui: `not_null` em `signed_quantity`, `gross_amount` e `is_possible_duplicate`, e `positive_value` em `gross_amount`. O `not_null` no `client_name` funciona como teste do join: se uma transação apontasse para um cliente fora do cadastro, ele falharia.

**Onde está.** `models/intermediate/int_transactions.sql`, `models/intermediate/schema.yml`.

---

# Marts

## D17. Fato incremental

**O que foi feito.** A `fact_transactions` é incremental, com esta configuração:

```sql
{{ config(
    materialized = 'incremental',
    unique_key = 'transaction_id',
    incremental_strategy = 'delete+insert',
    on_schema_change = 'fail'
) }}
```

Numa execução incremental, ela reprocessa só a janela recente:

```sql
where transaction_date >= (max(transaction_date) já carregada) - fact_lookback_days
```

**Por quê.**

- **A janela pega as transações atrasadas.** Uma transação que chega atrasada traz uma data igual ou anterior à maior já carregada. Reprocessar os últimos 3 dias a inclui. O `>=` garante que o dia da borda entre por inteiro. Validado: uma transação nova (T999) com a maior data já carregada entra na execução incremental.
- **`unique_key` com `delete+insert` deixa o reprocessamento idempotente.** As linhas da janela que já existem são apagadas e reinseridas, então rodar duas vezes não duplica. Validado: a segunda execução mantém 98 linhas.
- **`delete+insert` é estável no DuckDB e no Postgres** e fácil de explicar.
- **`on_schema_change = fail`.** Uma mudança de colunas quebra o run, em vez de passar sem ninguém perceber. Mudar o schema passa a exigir uma decisão consciente, com `dbt run --full-refresh`.

**Alternativas.** O tamanho da janela é configurável pela variável `fact_lookback_days` (padrão 3). As estratégias `merge` e `append` foram avaliadas e deixadas de fora para simplificar o modelo: `merge` dá o mesmo resultado para estes dados, e `append` duplicaria as linhas da janela a cada execução.

**Limitação.** A janela por data de transação não pega uma correção feita numa transação antiga, fora dos últimos 3 dias. Em produção, o filtro usaria uma coluna da fonte que registra quando a linha foi carregada ou alterada (`loaded_at` ou `updated_at`).

**Onde está.** `models/marts/fact_transactions.sql`, `dbt_project.yml` (variável `fact_lookback_days`).

## D18. O que a fato publica

**O que foi feito.** A fato não faz nenhuma transformação. Ela seleciona 11 colunas do `int_transactions`: identificação (`transaction_id`, `client_id`, `asset_ticker`), a operação (`operation_type`, `transaction_date`, `quantity`, `unit_price`), os valores (`signed_quantity`, `gross_amount`, `signed_amount`) e a flag `is_possible_duplicate`. Ficam de fora `client_name` e `client_state`.

**Por quê.** Nome e estado são atributos do cliente, e no modelo estrela eles pertencem à dimensão. A fato guarda o `client_id`, e quem precisa do nome faz o join com a `dim_clients`. Todo o cálculo fica no intermediate, e a fato só o materializa de forma incremental.

**Onde está.** `models/marts/fact_transactions.sql`.

## D19. Os marts leem da fato (estilo Kimball)

**O que foi feito.** O `mart_client_portfolio` e as métricas de atividade da `dim_clients` (primeira e última transação, total) leem da `fact_transactions`, e não do `int_transactions`. O cadastro da `dim_clients` continua vindo do `stg_clients`.

**Por quê.** É o desenho dimensional clássico: a fato é a fonte única das transações publicadas, e tudo que agrega transações parte dela. O portfólio fica sempre consistente com a fato que o consumidor também consulta, e a linhagem fica mais simples. Um `ref()` a um modelo incremental lê a tabela inteira, e não só a janela de reprocessamento, então os números são os mesmos de ler o intermediate: portfólio com 55 linhas e `dim_clients` com 25.

**Custo.** O portfólio herda qualquer limitação do incremental. Uma correção feita fora da janela (D17) não chega ao portfólio até um `--full-refresh`.

**Alternativa não implementada.** Os marts lerem direto do `int_transactions`, ao lado da fato. O portfólio seria sempre recalculado a partir da fonte completa e não herdaria as limitações do incremental, mas haveria dois caminhos de cálculo paralelos que poderiam divergir.

**Onde está.** `models/marts/mart_client_portfolio.sql`, `models/marts/dim_clients.sql`.

## D20. Dimensão de clientes

**O que foi feito.** A `dim_clients` tem uma linha por cliente, 25 no total. A CTE `clients` lê o cadastro do `stg_clients`, e a CTE `activity` agrupa a fato por cliente para calcular a primeira e a última transação e o total de transações. As duas se juntam com `left join`:

- `total_transactions` usa `coalesce(..., 0)`, então quem nunca operou aparece com zero, e não com nulo;
- `has_transactions` é verdadeiro quando o cliente aparece na `activity`.

**Por quê.** Dez clientes operaram, mas o cadastro tem 25. Com um `inner join`, os 15 que nunca operaram (C11 a C25) sumiriam. Uma dimensão que só tem quem transacionou não é uma dimensão de clientes.

**Chave da dimensão.** A chave é o `client_id` original, da origem. Com uma versão por cliente (D14) e um único sistema de origem, o ID natural é único e estável, e o projeto continua sem pacotes externos (D4).

Em produção, a chave seria uma **surrogate key**: uma chave gerada pelo data warehouse, por exemplo com `dbt_utils.generate_surrogate_key`, a partir do `client_id` e, num SCD tipo 2, do `valid_from`. Ela protege contra mudanças de ID na origem, permite juntar clientes de sistemas diferentes e é necessária quando a dimensão guarda várias versões do mesmo cliente (D14).

**Onde está.** `models/marts/dim_clients.sql`.

## D21. Métricas do portfólio

**O que foi feito.** O `mart_client_portfolio` tem uma linha por cliente e ativo, 55 no total, e três CTEs. A `transactions` lê a fato. A `aggregated` agrupa por cliente e ativo e soma. A `final` monta a chave e as colunas derivadas.

| Coluna | Cálculo | Significado |
|---|---|---|
| `net_quantity` | soma do `signed_quantity` | **Posição líquida em quantidade** (BUY − SELL): quantas ações o cliente tem |
| `net_amount` | soma do `signed_amount` | **Posição líquida em valor financeiro** (BUY − SELL), em reais |
| `total_bought_quantity`, `total_sold_quantity` | soma de `quantity` por tipo de operação | Quantas ações comprou e vendeu |
| `total_bought_amount`, `total_sold_amount` | soma de `gross_amount` por tipo de operação | Quanto comprou e vendeu, em reais |
| `avg_buy_price` | total comprado em reais ÷ quantidade comprada | Preço médio de compra |
| `portfolio_key` | `client_id` e `asset_ticker` concatenados | Chave do grão |
| `position_status` | `open`, `closed` ou `negative` | Situação da posição (D22) |

**Por quê.**

- **Os nomes seguem o enunciado.** O requisito 2 pede a "posição líquida (BUY − SELL em quantidade e valor financeiro)". As duas medidas viram duas colunas.
- **O `net_amount` não é volume, valor de mercado nem lucro.** Volume seria comprado *mais* vendido. Valor de mercado dependeria do preço atual. Lucro dependeria do custo médio das ações vendidas. Um `net_amount` negativo com `net_quantity` positivo é possível e legítimo: significa que o cliente vendeu mais em reais do que comprou e ainda tem ações. Hoje isso não ocorre nos dados.
- **O `avg_buy_price` considera só as compras**, e fica nulo se o cliente só vendeu o ativo, porque não existe preço médio de compra sem compra.
- **A `portfolio_key` permite testar a unicidade do grão** com o teste `unique` nativo, sem depender do `unique_combination_of_columns` do `dbt_utils`.
- **As somas de quantidade são convertidas para `bigint`.** O DuckDB devolveria `hugeint`, e o contrato exige o tipo declarado (D23).

**Onde está.** `models/marts/mart_client_portfolio.sql`, `models/docs.md` (descrição do `net_amount`).

## D22. Posições negativas: classificadas, não filtradas

**O que foi feito.** O portfólio mostra todas as posições, inclusive as zeradas e as negativas. A coluna `position_status` classifica cada uma: `open` (quantidade maior que zero), `closed` (igual a zero) ou `negative` (menor que zero). Hoje são 49 abertas e 6 negativas.

**Por quê.** O teste singular precisa ver as negativas (D8). Filtrá-las faria o teste passar escondendo o problema, que é justamente o "limpar os dados" que o enunciado proíbe. Com a classificação, quem consome decide o que fazer.

**Alternativa implementada só para mostrar o efeito.** `--vars '{portfolio_hide_negative_positions: true}'` remove as posições negativas. Validado: com ela, o teste singular passa até com severidade `error`, porque não sobra nada para ver. É a demonstração de por que essa opção é ruim.

**Onde está.** `models/marts/mart_client_portfolio.sql`.

## D23. Contratos nos marts

**O que foi feito.** Os três marts têm `contract: {enforced: true}`, com o tipo declarado para cada coluna. Os testes dos marts têm severidade `error`, e os `relationships` apontam para a `dim_clients` (D11).

**Por quê.** Os marts são a interface com quem consome. Com contrato, uma mudança de nome ou de tipo de coluna quebra o `dbt run`, em vez de chegar a um dashboard sem ninguém perceber. As colunas de texto são declaradas como `text`, que é o tipo nativo de texto no DuckDB e no Postgres (D1).

**Onde está.** `models/marts/schema.yml`.

---

# Macros e documentação

## D24. Macros

**O que foi feito.** Só virou macro a lógica que se repete:

| Macro | O que faz | Onde é usada |
|---|---|---|
| `clean_string(coluna)` | `nullif(trim(coluna), '')`: tira os espaços das pontas e transforma texto vazio em nulo | Nos dois modelos de staging |
| `deduplicate(relação, partição, ordenação)` | Numera as linhas com `row_number()` dentro de cada partição e mantém a primeira, segundo a ordenação passada | Nos dois modelos de staging |
| `count_nulls(colunas)` | Conta quantas das colunas passadas são nulas na linha | No `stg_clients`, como critério da deduplicação |
| `duckdb__safe_cast(campo, tipo)` | Override do `dbt.safe_cast` que usa `try_cast` | Em todo `dbt.safe_cast` executado no DuckDB |

**Detalhes.**

- **`deduplicate`**: a ordenação precisa ser determinística, com um desempate, para o resultado não mudar entre execuções. Nas transações, a partição é o `transaction_id` e fica a de data mais antiga. Nos clientes, a partição é o `client_id` e fica a mais completa (D14).
- **`clean_string`**: o `dbt seed` já carrega um campo vazio como nulo (é o caso da T021). A macro cobre também um texto que só tenha espaços.
- **`duckdb__safe_cast`**: no dbt-duckdb, o `safe_cast` padrão compila para um `cast` comum, que falha com um valor como `quantity = 'abc'` e derruba o `dbt run`. O override usa `try_cast`, que devolve nulo, e o staging filtra esse nulo (D13). O dbt procura primeiro uma macro do projeto com o prefixo do adaptador, por isso o nome `duckdb__`. No Postgres não existe `try_cast`, então lá vale o comportamento padrão: com os dados do desafio o resultado é o mesmo, mas um valor sujo derrubaria o `dbt run`. Validado trocando uma quantidade por `abc` numa cópia do CSV: no DuckDB o `dbt run` passa e a linha sai do staging.

Os testes genéricos `positive_value` e `unique_combination` (D10) também são código reutilizável escrito no projeto.

**O que não virou macro.** O `signed_quantity`, porque aparece num lugar só, e o SQL direto é mais legível.

**Onde está.** `macros/`.

## D25. Descrições das colunas

**O que foi feito.** Toda coluna de todo modelo e de todo seed tem descrição, como pede o requisito 5. As descrições que se repetem entre camadas (`client_id`, `transaction_id`, `net_amount` e outras) ficam em doc blocks no `models/docs.md` e são referenciadas com `{{ doc('...') }}`.

**Por quê.** Uma descrição repetida em quatro `schema.yml` acaba divergindo com o tempo. Com o doc block, ela existe num lugar só. O `dbt docs generate` roda sem avisos.

**Onde está.** `models/docs.md` e os `schema.yml`.

---

# Problemas nos dados e onde cada um aparece

| Registro | Problema | Teste que sinaliza (`warn`) | Tratamento |
|---|---|---|---|
| T021 | `client_id` vazio | `not_null_transactions_client_id` | Filtrada no staging (D13) |
| T037 | Compra com quantidade −50 | `positive_value_transactions_quantity` | Filtrada no staging (D13) |
| T035 e T036 | Idênticas, exceto no ID | `transactions_unique_content_except_id` | Mantidas e sinalizadas (D15) |
| C1 | Linha duplicada, idêntica | `unique_clients_client_id` | Deduplicado (D14) |
| C6 | Duplicado, uma cópia sem cidade | `unique_clients_client_id`, `not_null_clients_city` | Fica a versão com cidade (D14) |
| C1, C3, C5, C6, C7, C8 | Posição final negativa em 6 pares cliente e ativo | `assert_no_negative_position` | Mantidas e sinalizadas (D8, D22) |
| C11 a C25 | Clientes sem nenhuma transação | Nenhum: não é um erro | Aparecem na dimensão com `has_transactions = false` (D20) |
