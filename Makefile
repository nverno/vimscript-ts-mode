SHELL   =  /bin/bash

TS_REPO     ?= https://github.com/neovim/tree-sitter-vim
TSDIR       =  $(notdir $(TS_REPO))
VIM_VERSION ?= $(shell vim --version |                                        \
		awk 'NR==1 {print gensub(/[^0-9]*([0-9.]+).*/, "\\1", 1)}' || \
		echo "8.0")

all:
	@

keywords: vim-builtins.txt
vim-builtins.txt:
	$(CURDIR)/bin/vimwords.py -v $(VIM_VERSION) -o $@ || rm $@

# Tree-sitter
dev: $(TSDIR)
$(TSDIR):
	@git clone --depth=1 $(TS_REPO)
	@printf "\e[1m\e[31mNote\e[22m\e[0m npm build can take a while\n" >&2
	cd $(TSDIR) &&                                         \
		npm --loglevel=info --progress=true install && \
		npm run generate

.PHONY: parse-%
parse-%:
	cd $(TSDIR) && npx tree-sitter parse $(TESTDIR)/$(subst parse-,,$@)

clean:
	$(RM) *~
