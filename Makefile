.PHONY: help ci lint lint-docs test test-stage-a check check-all drift fix \
	update update-full vm-a vm-b vm-clean secrets-init secrets-unlock

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

help: ## Show available targets
	@awk -F ':.*## ' '/^[a-zA-Z0-9_-]+:.*## / { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

ci: lint test test-stage-a lint-docs ## Run full local CI (exact mirror of .github/workflows/ci.yml)
	@rc=0; git grep -nIE \
		-e '-----BEGIN (RSA|EC|OPENSSH|DSA|PGP) PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|sk-ant-[A-Za-z0-9-]{20,}|sk-[A-Za-z0-9]{32,}' \
		-- ':!.github/workflows/ci.yml' ':!Makefile' || rc=$$?; \
		if [[ $$rc -ne 1 ]]; then echo "FAIL: secret scan exited $$rc" >&2; exit 1; fi
	@diff -u all_stow_files.txt <(bash scripts/list-stow-files.sh)
	@! grep -Eiq 'Cache|/CacheStorage/|lazy-lock\.json' all_stow_files.txt
	@echo "PASS: make ci"

lint: ## Run bash -n and ShellCheck on all scripts
	@while IFS= read -r -d '' f; do bash -n "$$f"; done < <(find scripts system ai desktop security provision builds labs -type f -name '*.sh' -print0)
	@bash -n install.sh stow-only.sh
	@while IFS= read -r -d '' f; do bash -n "$$f"; done < <(find profiles -type f -name '*.sh' -print0 2>/dev/null || true)
	@shellcheck -x -S warning -s bash \
		install.sh stow-only.sh \
		scripts/*.sh scripts/check.d/*.sh \
		provision/scripts/*.sh provision/lib/*.sh \
		system/scripts/*.sh \
		ai/scripts/*.sh ai/lib/*.sh \
		desktop/scripts/*.sh desktop/lib/*.sh \
		security/scripts/*.sh security/lib/*.sh \
		builds/scripts/*.sh \
		profiles/*.sh labs/*/*.sh \
		ai/rules/install.sh ai/rules/bin/agentsync ai/rules/lib/*.sh \
		ai/rules/git-hooks/* stow/git/.config/git/templates/hooks/*

lint-docs: ## Run markdownlint on all repository markdown docs
	@bash scripts/lint-docs.sh

test: ## Run all dotfiles unit tests
	@for t in tests/*.test.sh; do bash "$$t"; done

test-stage-a: ## Run Stage A (t14s-arch-install) tests and ShellCheck
	@cd t14s-arch-install && \
		bash tests/host-check.test.sh && \
		bash tests/smoke.test.sh && \
		shellcheck -S warning -e SC2015,SC2086,SC2162,SC2034 install.sh && \
		shellcheck -S warning -e SC2015,SC2086,SC2162,SC2034,SC1090,SC1091,SC2154 lib/*.sh lib/steps/*.sh lib/chroot/*.sh && \
		shellcheck -S warning tests/host-check.sh tests/host-check.test.sh tests/vm-run.sh tests/vm-bootstrap.sh tests/vm-dual-bootstrap.sh

check: ## Run Stage B health check (scripts/check.sh --post)
	@bash scripts/check.sh --post

check-all: ## Run Stage A + Stage B health checks
	@bash scripts/check.sh --all

drift: ## Check package and stow symlink drift
	@bash scripts/check.sh --drift

fix: ## Run safe idempotent fixes then re-check
	@bash scripts/check.sh --fix

update: ## Run standard post-update maintenance
	@bash provision/scripts/post-update.sh

update-full: ## Run full system + AI skills + health check update
	@bash provision/scripts/post-update.sh --full

vm-a: ## Run bare-disk Stage A VM install (ISO=... FRESH=1)
	@bash t14s-arch-install/tests/vm-run.sh

vm-b: ## Run Stage B VM install on qcow2 overlay (preserves Stage A disk)
	@bash provision/scripts/vm-stageb-run.sh

vm-clean: ## Remove ~/arch-vmtest VM images and logs
	@rm -rf "$${WORK:-$$HOME/arch-vmtest}"
	@echo "Cleaned $${WORK:-$$HOME/arch-vmtest}"

secrets-init: ## Initialize encrypted local machine overrides (~/.config/dotfiles/local.env)
	@bash security/scripts/secrets-bootstrap.sh init

secrets-unlock: ## Decrypt local machine overrides to ~/.config/dotfiles/local.env
	@bash security/scripts/secrets-bootstrap.sh unlock
