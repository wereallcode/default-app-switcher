CONFIGURATION ?= release

.PHONY: all build check test lint format format-check clean run hooks

all: build

build:
	@CONFIGURATION="$(CONFIGURATION)" scripts/build.sh

check:
	@$(MAKE) lint
	@$(MAKE) format-check
	@$(MAKE) test
	@$(MAKE) build

test:
	@swift run --package-path app -c debug DASTests
	@bash scripts/tests/metadata.sh
	@bash scripts/tests/install.sh

lint:
	@for script in scripts/*.sh scripts/tests/*.sh .githooks/*; do bash -n "$$script" || exit 1; done
	@bash scripts/check.sh

format:
	@swift format format --in-place --recursive app/Package.swift app/Sources app/Tests

format-check:
	@swift format lint --strict --recursive app/Package.swift app/Sources app/Tests

run: build
	@dist/das

clean:
	@swift package --package-path app clean && rm -rf dist
	@printf 'Build files removed.\n'

hooks:
	@git config core.hooksPath .githooks
	@printf 'Git hooks enabled from .githooks.\n'
