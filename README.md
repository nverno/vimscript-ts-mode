# Vim script major mode using tree-sitter

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

This package provides a major-mode for vimscript using the tree-sitter 
grammar from https://github.com/neovim/tree-sitter-vim.

Features:
- indentation
- font-locking
- imenu
- structural navigation with treesitter objects

![example](doc/vimscript-example.png)

## Installing

Emacs 29.1 or above with tree-sitter support is required. 

Tree-sitter starter guide: https://git.savannah.gnu.org/cgit/emacs.git/tree/admin/notes/tree-sitter/starter-guide?h=emacs-29

### Install tree-sitter parser for vim

Add the source to `treesit-language-source-alist`. 

```elisp
(add-to-list
 'treesit-language-source-alist
 '(vim "https://github.com/neovim/tree-sitter-vim"))
```

Then run `M-x treesit-install-language-grammar` and select `vim` to install.

### Install vimscript-ts-mode.el from source

- Clone this repository
- Add the following to your emacs config

```elisp
(require "[cloned nverno/vimscript-ts-mode]/vimscript-ts-mode.el")
```

### Troubleshooting

If you get the following warning:

```
⛔ Warning (treesit): Cannot activate tree-sitter, because tree-sitter
library is not compiled with Emacs [2 times]
```

Then you do not have tree-sitter support for your emacs installation.

If you get the following warnings:
```
⛔ Warning (treesit): Cannot activate tree-sitter, because language grammar for vim is unavailable (not-found): (libtree-sitter-vim libtree-sitter-vim.so) No such file or directory
```

then the vim grammar files are not properly installed on your system.
