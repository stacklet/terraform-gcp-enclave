# format all files
format: format-tf format-go

# format terraform files
format-tf:
    terraform fmt -recursive

# format go files
format-go:
    gofmt -w relay_forwarder/

# lint files
lint: lint-tf lint-go lint-docs

# lint terraform files
lint-tf:
    #!/usr/bin/env bash
    set -e

    terraform fmt -recursive --check
    terraform init
    terraform validate
    tflint -f compact --recursive

# lint go files
lint-go:
    cd relay_forwarder && go vet ./...

# lint readme
lint-docs:
    terraform-docs --output-check .

docs:
    terraform-docs .

# run go tests
test:
    cd relay_forwarder && go test -race ./...
