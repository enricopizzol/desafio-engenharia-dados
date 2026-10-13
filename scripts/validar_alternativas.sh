#!/usr/bin/env bash
# Roda cada alternativa do doc de decisões (decisoes.md) e confere o resultado
# esperado. Usa um banco separado para não mexer no cdv.duckdb do dia a dia.
# Uso: bash scripts/validar_alternativas.sh   (com o venv ativado)
set -u
cd "$(dirname "$0")/.."
export DBT_DUCKDB_PATH="${DBT_DUCKDB_PATH:-alternativas.duckdb}"

passed=0; failed=0

check() {  # check "descrição" código_esperado comando...
    local desc="$1" expected="$2"; shift 2
    "$@" > /tmp/dbt_alt.log 2>&1
    local got=$?
    if [ "$got" -eq "$expected" ]; then
        echo "OK    $desc (saída $got)"; passed=$((passed+1))
    else
        echo "FALHA $desc (esperado $expected, veio $got)"; failed=$((failed+1))
        tail -20 /tmp/dbt_alt.log
    fi
}

count() {  # count "sql" -> imprime o primeiro valor do resultado
    python -c "import duckdb,sys; print(duckdb.connect(sys.argv[1], read_only=True).sql(sys.argv[2]).fetchone()[0])" \
        "$DBT_DUCKDB_PATH" "$1"
}

expect_count() {  # expect_count "descrição" esperado "sql"
    local got; got=$(count "$3")
    if [ "$got" = "$2" ]; then echo "OK    $1 = $got"; passed=$((passed+1))
    else echo "FALHA $1: esperado $2, veio $got"; failed=$((failed+1)); fi
}

rm -f "$DBT_DUCKDB_PATH"

echo "== Padrão (D3, D4): seed, run e test passam com avisos"
check "dbt seed" 0 dbt seed
check "dbt run" 0 dbt run --full-refresh
check "dbt test (WARN, código 0)" 0 dbt test
expect_count "linhas na fact" 98 "select count(*) from main.fact_transactions"
expect_count "clientes na dim" 25 "select count(*) from main.dim_clients"
expect_count "posições negativas" 6 "select count(*) from main.mart_client_portfolio where net_quantity < 0"
expect_count "falhas gravadas na auditoria" 6 "select count(*) from main_dbt_test__audit.assert_no_negative_position"

echo "== D3 alternativa: modo estrito no teste singular"
check "severidade error (código 1)" 1 dbt test --select assert_no_negative_position --vars '{negative_position_severity: error}'

echo "== D3 alternativa: limiares"
# Limiares só valem com severity error: com warn o dbt nunca avalia error_if.
check "error se >10 (6 negativas: WARN, código 0)" 0 dbt test --select assert_no_negative_position --vars '{negative_position_severity: error, negative_position_error_if: ">10"}'
check "error se >5 (6 negativas: ERROR, código 1)" 1 dbt test --select assert_no_negative_position --vars '{negative_position_severity: error, negative_position_error_if: ">5"}'

echo "== D4 alternativa: testes da fonte bloqueantes"
check "source_quality_severity error (código 1)" 1 dbt test --select "resource_type:seed" --vars '{source_quality_severity: error}'
check "seeds bloqueantes, mas camadas seguem passando" 0 dbt test --exclude "resource_type:seed" assert_no_negative_position assert_no_negative_running_position

echo "== D17: posição acumulada negativa"
check "modo estrito do teste acumulado (código 1)" 1 dbt test --select assert_no_negative_running_position --vars '{negative_running_position_severity: error}'

echo "== D9 alternativa: deduplicar T035/T036 pelo conteúdo"
check "run com dedup por conteúdo" 0 dbt run --full-refresh --vars '{dedup_transactions_by_content: true}'
expect_count "linhas na fact com dedup" 97 "select count(*) from main.fact_transactions"
expect_count "C4 ITUB4 com dedup" 120 "select net_quantity from main.mart_client_portfolio where portfolio_key = 'C4|ITUB4'"
check "testes das camadas passam com dedup" 0 dbt test --exclude "resource_type:seed" --vars '{dedup_transactions_by_content: true}'
check "volta ao padrão" 0 dbt run --full-refresh
expect_count "C4 ITUB4 padrão" 240 "select net_quantity from main.mart_client_portfolio where portfolio_key = 'C4|ITUB4'"

echo "== D11 rejeitada: esconder negativas no mart"
check "run escondendo negativas" 0 dbt run --select mart_client_portfolio --vars '{portfolio_hide_negative_positions: true}'
check "teste singular passa sem achar nada (o problema sumiu da vista)" 0 dbt test --select assert_no_negative_position --vars '{negative_position_severity: error}'
check "volta ao padrão" 0 dbt run --select mart_client_portfolio

echo "== D13: incremental"
for strategy in delete+insert merge; do
    check "full refresh ($strategy)" 0 dbt run --select fact_transactions --full-refresh --vars "{fact_incremental_strategy: $strategy}"
    check "segunda execução incremental ($strategy)" 0 dbt run --select fact_transactions --vars "{fact_incremental_strategy: $strategy}"
    expect_count "linhas após reprocessar a janela ($strategy)" 98 "select count(*) from main.fact_transactions"
done
check "full refresh (append)" 0 dbt run --select fact_transactions --full-refresh --vars '{fact_incremental_strategy: append}'
check "segunda execução incremental (append)" 0 dbt run --select fact_transactions --vars '{fact_incremental_strategy: append}'
expect_count "append duplica a janela (98 + transações dos últimos 3 dias)" 100 "select count(*) from main.fact_transactions"
check "append: teste unique da fact falha (código 1)" 1 dbt test --select fact_transactions
check "volta ao padrão" 0 dbt run --select fact_transactions --full-refresh

echo "== D13: transação atrasada com data já carregada"
cp seeds/transactions.csv /tmp/transactions.csv.bak
max_date=$(count "select max(transaction_date) from main.fact_transactions")
printf 'T999,C9,PETR4,BUY,10,40.00,%s\n' "$max_date" >> seeds/transactions.csv
check "seed com a linha nova" 0 dbt seed --select transactions
check "run incremental" 0 dbt run --select +fact_transactions
expect_count "T999 entrou pela janela" 99 "select count(*) from main.fact_transactions"
cp /tmp/transactions.csv.bak seeds/transactions.csv
check "restaura o seed" 0 dbt seed --select transactions
check "volta ao padrão" 0 dbt run --full-refresh

echo "== dbt build (alternativa a seed + run + test)"
check "dbt build" 0 dbt build

echo
echo "Resultado: $passed OK, $failed FALHA"
rm -f "$DBT_DUCKDB_PATH"
[ "$failed" -eq 0 ]
