SHELL := /usr/bin/env fish

.PHONY: all
all: fmt lint install test

.PHONY: fmt
fmt:
	@fish_indent --write **.fish

.PHONY: lint
lint:
	@for file in **.fish; fish --no-execute $$file; end

.PHONY: install
install:
	@type -q fisher || begin; curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher; end
	@fisher install . >/dev/null

littlecheck.py:
	@curl -sL https://raw.githubusercontent.com/ridiculousfish/littlecheck/HEAD/littlecheck/littlecheck.py -o littlecheck.py

.PHONY: test
test: install littlecheck.py
	@type -q mock || fisher install IlanCosman/clownfish
	@fish tests/test_cleanup.fish
	@fish tests/test_setup.fish
	@_tide_remove_unusable_items
	@begin; _tide_cache_variables; python3 littlecheck.py --progress tests/**.test.fish; set -l test_status $$status; fish tests/test_cleanup.fish; exit $$test_status; end

.PHONY: clean
clean:
	@rm littlecheck.py
