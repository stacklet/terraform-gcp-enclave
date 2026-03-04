# format terraform and go files
format:
    terraform fmt -recursive
    gofmt -w relay_forwarder/

# lint terraform and go files
lint:
    #!/usr/bin/env bash
    set -e

    terraform fmt -recursive --check
    terraform init
    terraform validate
    tflint -f compact --recursive
    go vet ./relay_forwarder/...

docs:
    terraform-docs .

# run go tests
test:
    cd relay_forwarder && go test -race ./...
