# format all files
format: format-tf format-go

# format terraform files
format-tf:
    terraform fmt -recursive

# format go files
format-go:
    env -C relay_forwarder go fmt ./...

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
    #!/usr/bin/env bash
    set -e

    cd relay_forwarder
    go vet ./...
    golangci-lint run --fix

# lint readme
lint-docs:
    terraform-docs --output-check .

docs:
    terraform-docs .

# run go tests
test:
    env -C relay_forwarder go test -race ./...

# Update golang dependencies
update-deps-go:
    #!/usr/bin/env bash
    set -e

    cd relay_forwarder
    go get -u
    go mod tidy
