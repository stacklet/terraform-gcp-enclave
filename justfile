# format terraform files
format:
    terraform fmt -recursive

# lint files
lint: lint-tf lint-docs

# lint terraform files
lint-tf:
    #!/usr/bin/env bash
    set -e

    terraform fmt -recursive --check
    terraform init
    terraform validate
    tflint -f compact --recursive

# lint readme
lint-docs:
    terraform-docs --output-check .

docs:
    terraform-docs .
