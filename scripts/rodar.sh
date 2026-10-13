#!/usr/bin/env bash
# Atalho para Linux e macOS: cria o ambiente virtual, instala as dependências
# e roda dbt seed, dbt run e dbt test. Não precisa ativar nada antes.
# Uso: bash scripts/rodar.sh
set -euo pipefail
cd "$(dirname "$0")/.."

py=""
for cand in python3.13 python3.12 python3.11 python3.10 python3 python; do
    if command -v "$cand" > /dev/null 2>&1 \
        && "$cand" -c 'import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)' 2> /dev/null; then
        py="$cand"; break
    fi
done
if [ -z "$py" ]; then
    echo "ERRO: é preciso Python 3.10 a 3.13 (veja o README, seção Pré-requisitos)." >&2
    exit 1
fi

if [ ! -x .venv/bin/dbt ]; then
    echo ">> Criando .venv com $("$py" --version)"
    rm -rf .venv
    if ! "$py" -m venv .venv; then
        echo "ERRO: não foi possível criar o .venv. No Ubuntu e no Debian, rode" >&2
        echo "      'sudo apt install python3-venv' e tente de novo." >&2
        exit 1
    fi
    echo ">> Instalando dependências"
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet -r requirements.txt
fi

.venv/bin/dbt --version
.venv/bin/dbt seed
.venv/bin/dbt run
.venv/bin/dbt test
