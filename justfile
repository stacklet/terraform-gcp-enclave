# format terraform and python files
format:
    terraform fmt -recursive
    uv run ruff check --fix relay_forwarder/ tests/
    uv run ruff format relay_forwarder/ tests/

# lint terraform and python files
lint:
    #!/usr/bin/env bash
    set -e

    terraform fmt -recursive --check
    terraform init
    terraform validate
    tflint -f compact --recursive
    uv run ruff check relay_forwarder/ tests/
    uv run mypy

docs:
    terraform-docs .

# sync python dev environment and regenerate requirements.txt
sync:
    uv sync
    uv export --no-dev --no-hashes --no-emit-project --output-file relay_forwarder/requirements.txt

# run python tests
test:
    uv run pytest
