{% docs client_id %}
Identificador do cliente (ex.: `C1`). Chave de `dim_clients`.
{% enddocs %}

{% docs transaction_id %}
Identificador da transação (ex.: `T001`). Chave de `fact_transactions`.
{% enddocs %}

{% docs asset_ticker %}
Código de negociação do ativo na B3 (ex.: `PETR4`).
{% enddocs %}

{% docs operation_type %}
Tipo da operação: `BUY` (compra) ou `SELL` (venda).
{% enddocs %}

{% docs quantity %}
Quantidade de ações negociadas, sempre positiva. O sentido vem de `operation_type`.
{% enddocs %}

{% docs unit_price %}
Preço unitário em reais, `decimal(18,4)`.
{% enddocs %}

{% docs transaction_date %}
Data da operação.
{% enddocs %}

{% docs signed_quantity %}
Quantidade com sinal: positiva em compras, negativa em vendas.
{% enddocs %}

{% docs gross_amount %}
Valor bruto da operação, `quantity * unit_price`, em reais.
{% enddocs %}

{% docs signed_amount %}
Valor com sinal: positivo em compras (dinheiro investido), negativo em vendas (dinheiro recebido).
{% enddocs %}

{% docs is_possible_duplicate %}
Verdadeiro quando existe outra transação com o mesmo cliente, ativo, operação, quantidade, preço e data
(caso T035/T036). Por padrão as duas são mantidas; ver decisão D9 em `decisoes.md`.
{% enddocs %}

{% docs net_amount %}
Fluxo financeiro líquido: total comprado em reais menos total vendido em reais.
**Não** é valor de mercado nem custo da posição; pode ser negativo com quantidade positiva quando há lucro realizado.
{% enddocs %}
