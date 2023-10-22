;;; vimscript-ts-mode.el --- Vim-script major mode using tree-sitter -*- lexical-binding: t; -*-

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/vimscript-ts-mode
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))
;; Created:  11 October 2023
;; Keywords: languages vim tree-sitter

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; This package defines a major mode for vimscript buffers using the
;; tree-sitter parser from https://github.com/neovim/tree-sitter-vim.
;; 
;; It provides the following features:
;;  - indentation
;;  - font-locking
;;  - imenu
;;  - structural navigation using tree-sitter objects
;;
;; When parsers are available for lua or ruby, they will be used to
;; parse embedded code blocks. See `lua-ts-mode' and `ruby-ts-mode'
;; for more information about those parsers.
;;
;;; Installation:
;;
;; Install the tree-sitter grammar for vim
;;
;;     (add-to-list
;;      'treesit-language-source-alist
;;      '(vim "https://github.com/neovim/tree-sitter-vim"))
;; 
;; Optionally, install grammars for `lua-ts-mode' and `ruby-ts-mode' to
;; enable font-locking/indentation for embedded lua / ruby code.
;;
;; And call `treesit-install-language-grammar' to complete the installation.
;;
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'seq)
(require 'treesit)

(defcustom vimscript-ts-mode-indent-level 2
  "Number of spaces for each indententation step."
  :group 'vim
  :type 'integer
  :safe 'integerp)

(defface vimscript-ts-mode-register-face
  '((t (:inherit font-lock-variable-name-face :weight bold)))
  "Face to highlight registers in `vimscript-ts-mode'."
  :group 'vim)

(defface vimscript-ts-mode-keycode-face
  '((t (:inherit font-lock-constant-face :slant italic)))
  "Face to highlight keycodes in `vimscript-ts-mode'."
  :group 'vim)

(defface vimscript-ts-mode-scope-face
  '((t (:inherit font-lock-type-face :slant italic)))
  "Face to highlight namespaces in `vimscript-ts-mode'."
  :group 'vim)

(defface vimscript-ts-mode-regexp-face
  '((t (:inherit font-lock-regexp-face)))
  "Face to highlight regexps in `vimscript-ts-mode'."
  :group 'vim)

(defface vimscript-ts-mode-heredoc-face
  '((t (:inherit font-lock-preprocessor-face)))
  "Face to highlight here-documents in `vimscript-ts-mode'."
  :group 'vim)

(defface vimscript-ts-mode-embedded-face
  '((t :inherit (org-block) :extend t))
  "Face to highlight embedded language blocks.")

;;; Syntax

(defvar vimscript-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?'  "\"" table)
    (modify-syntax-entry ?\" "<"  table)
    (modify-syntax-entry ?\n ">"  table)
    (modify-syntax-entry ?#  "_"  table)
    (modify-syntax-entry ?& "'" table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?* "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?@ "." table)
    table)
  "Syntax table in use in Vimscript buffers.")

;;; Indentation

(defvar vimscript-ts-mode--indent-rules
  '((vim
     ((parent-is "script_file") parent 0)
     ((node-is ")") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "else") parent-bol 0)
     ((node-is "endif") parent-bol 0)
     ((node-is "endwhile") parent-bol 0)
     ((node-is "endfor") parent-bol 0)
     ((node-is "endfunction") parent-bol 0)
     ((node-is "endfunc") parent-bol 0)
     ((node-is "catch") parent-bol 0)
     ((node-is "finally") parent-bol 0)
     ((node-is "endtry") parent-bol 0)
     ((node-is "endmarker") grand-parent 0)
     ((n-p-gp "" "body" "heredoc") no-indent 0)
     ((n-p-gp "" "body" "script") no-indent)
     ((n-p-gp "" "body" "else_statement") grand-parent vimscript-ts-mode-indent-level)
     ((parent-is "body") parent-bol 0)
     ((parent-is "heredoc") no-indent)
     (no-node parent-bol vimscript-ts-mode-indent-level)
     (catch-all parent-bol vimscript-ts-mode-indent-level)))
  "Tree-sitter indentation rules for vimscript.")

;;; Font-Lock

(defvar vimscript-ts-mode--feature-list
  '(( comment definition)
    ( keyword string)
    ( assignment property type constant literal operator function
      escape-sequence embedded)
    ( bracket delimiter variable misc-punctuation)) ;; error
  "`treesit-font-lock-feature-list' for `vimscript-ts-mode'.")

(defvar vimscript-ts-mode--operators
  '("||" "&&" "&" "+" "-" "*" "/" "%" ".." "is" "isnot" "==" "!=" ">" ">=" "<"
    "<=" "=~" "!~" "=" "+=" "-=" "*=" "/=" "%=" ".=" "..=" "<<" "=<<"
    "->" "++")
  "Vimscript operators for tree-sitter font-locking.")

(defvar vimscript-ts-mode--keywords
  '("if" "else" "elseif" "endif"        ; conditionals
    "try" "catch" "finally" "endtry" "throw" ; exceptions
    "for" "endfor" "in" "while" "endwhile" "break" "continue" ; loops
    "function" "endfunction" "return" "dict" "range" "abort" "closure" ; functions
    ;; filetype
    "detect" "plugin" "indent" "on" "off"
    ;; syntax statement
    "enable" "on" "off" "reset" "case" "spell" "foldlevel" "iskeyword"
    "keyword" "match" "cluster" "region" "clear" "include"
    ;; highlight statement
    "default" "link" "clear"
    ;; command and user-defined commands
    "let" "unlet" "const" "call" "execute" "normal" "set" "setfiletype" "setlocal"
    "silent" "echo" "echon" "echohl" "echomsg" "echoerr" "autocmd" "augroup"
    "return" "syntax" "filetype" "source" "lua" "ruby" "perl" "python" "highlight"
    "command" "delcommand" "comclear" "colorscheme" "startinsert" "stopinsert"
    "global" "runtime" "wincmd" "cnext" "cprevious" "cNext" "vertical" "leftabove"
    "aboveleft" "rightbelow" "belowright" "topleft" "botright"
    "edit" "enew" "find" "ex" "visual" "view" "eval")
  "Vimscript keywords for tree-sitter font-locking.")

(defun vimscript-ts-mode--fontify-syntax-pattern (node override &rest _)
  "Fontify pattern NODE with OVERRIDE."
  (let ((beg (treesit-node-start node))
        (end (treesit-node-end node)))
    (treesit-fontify-with-override      ; include '/' (pattern) '/' in highlight
     (1- beg) (1+ end) 'vimscript-ts-mode-regexp-face override)))

(defun vimscript-ts-mode--fontify-escape (node override &rest _)
  "Fontify escape sequence NODE with OVERRIDE."
  (let* ((beg (treesit-node-start node))
         (end (treesit-node-end node))
         (face (pcase (char-after end)
                 ((or ?. ?* ?~ ?\\ ?^ ?$ ?/ ?\[ ?\] 32) ; lose their magic
                  'font-lock-negation-char-face)
                 ((or ?_ ?z ?%)         ; three char escapes, eg. \zs
                  (cl-incf end 2)
                  'font-lock-escape-face)
                 (?@ (cl-incf end)      ; lookahead
                     'font-lock-operator-face)
                 (_ (cl-incf end)       ; two char escapes
                    'font-lock-escape-face))))
    (treesit-fontify-with-override beg end face override)))

(defvar vimscript-ts-mode--s-p-query
  (when (treesit-available-p)
    (treesit-query-compile
     'vim
     '(((syntax_argument (pattern) @regexp))
       ((syntax_statement (pattern) @regexp))
       ((string_literal) @string)))))

(defun vimscript-ts-mode--syntax-propertize (start end)
  "Apply syntax text properties between START and END for `vimscript-ts-mode'."
  (let ((captures (treesit-query-capture 'vim vimscript-ts-mode--s-p-query start end)))
    (pcase-dolist (`(,name . ,node) captures)
      (let* ((ns (treesit-node-start node))
             (ne (treesit-node-end node))
             (syntax (pcase-exhaustive name
                       ('regexp
                        (cl-decf ns)
                        (cl-incf ne)
                        (string-to-syntax "|"))
                       ('string
                        (string-to-syntax "\"")))))
        (put-text-property ns (1+ ns) 'syntax-table syntax)
        (put-text-property (1- ne) ne 'syntax-table syntax)))))

(defvar vimscript-ts-mode--font-lock-embedded
  (treesit-font-lock-rules
   :language 'vim
   :feature 'embedded
   :override 'append
   ;; ([lua|python|perl|ruby]_statement (chunk))
   '((chunk) @vimscript-ts-mode-embedded-face
     (script (body) @vimscript-ts-mode-embedded-face)))
  "Font-locking for embedded language blocks.")

(defvar vimscript-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'vim
   :feature 'comment
   '([(comment) (line_continuation_comment)] @font-lock-comment-face)

   :language 'vim
   :feature 'string
   '((binary_operation
      _ "=~" (match_case) :?
      right: (string_literal) @vimscript-ts-mode-regexp-face)
     (syntax_argument [(pattern)] @vimscript-ts-mode--fontify-syntax-pattern)
     (syntax_statement [(pattern)] @vimscript-ts-mode--fontify-syntax-pattern)
     [(pattern) (pattern_multi)] @vimscript-ts-mode-regexp-face
     
     [(command) (filename) (string_literal)] @font-lock-string-face
     (heredoc (body) @font-lock-string-face)
     (colorscheme_statement (name) @font-lock-string-face)
     (syntax_statement (keyword) @font-lock-string-face))
   
   :language 'vim
   :feature 'escape-sequence
   :override 'prepend
   `((pattern ["\\"] @vimscript-ts-mode--fontify-escape)
     (pattern ["\\&"] @font-lock-operator-face)

     ((pattern_multi) @font-lock-number-face
      (:match ,(rx "\\{") @font-lock-number-face))
     (pattern_multi) @font-lock-operator-face
     
     ["\\|" "\\(" "\\)" "\\%(" "\\z("] @font-lock-regexp-grouping-construct)
   
   :language 'vim
   :feature 'keyword
   `([,@vimscript-ts-mode--keywords (unknown_command_name)] @font-lock-keyword-face
     (heredoc (parameter) @font-lock-keyword-face)
     (runtime_statement (where) @font-lock-keyword-face)
     (syntax_argument name: _ @font-lock-keyword-face)
     (map_statement cmd: _ @font-lock-keyword-face)
     ["<buffer>" "<nowait>" "<silent>" "<script>" "<expr>" "<unique>"]
     @font-lock-builtin-face)

   :language 'vim
   :feature 'definition
   '((function_declaration
      name: (_) @font-lock-function-name-face)

     (command_name) @font-lock-function-name-face

     (bang) @font-lock-warning-face
     (register) @vimscript-ts-mode-register-face

     (default_parameter (identifier) @font-lock-variable-name-face)
     (parameters [(identifier)] @font-lock-variable-name-face)
     [(no_option) (inv_option) (default_option) (option_name)] @font-lock-variable-name-face
     (lambda_expression "{" [(identifier)] @font-lock-variable-name-face "->")
     
     [(marker_definition) (endmarker)] @font-lock-type-face)
   
   :language 'vim
   :feature 'property
   '((command_attribute
      name: _ @font-lock-property-name-face
      val: (behavior
            name: _ @font-lock-constant-face
            val: (identifier) @font-lock-function-name-face :?)
      :?)
     
     (hl_attribute
      key: _ @font-lock-property-name-face)

     (plus_plus_opt
      name: _ @font-lock-property-name-face
      val: _ @font-lock-constant-face :?)
     (plus_cmd) @font-lock-property-name-face

     (dictionnary_entry
      key: (_) @font-lock-property-name-face))

   :language 'vim
   :feature 'type
   :override 'prepend
   '((augroup_name) @vimscript-ts-mode-scope-face
     (keycode) @vimscript-ts-mode-keycode-face
     (hl_group) @vimscript-ts-mode-scope-face
     [(scope) (scope_dict) "a:" "$"] @vimscript-ts-mode-scope-face)
   
   :language 'vim
   :feature 'constant
   '(((identifier) @font-lock-constant-face
      (:match "\\`[A-Z][A-Z_0-9]*\\'" @font-lock-constant-face))
     [(au_event) (au_once) (au_nested)] @font-lock-constant-face
     (normal_statement (commands) @font-lock-constant-face)
     (hl_attribute _ "=" _ @font-lock-constant-face))
   
   :language 'vim
   :feature 'literal
   '([(float_literal) (integer_literal)] @font-lock-number-face
     ((set_value) @font-lock-number-face
      (:match "\\`[0-9]+\\(?:[.][0-9]+\\)?\\'" @font-lock-number-face))
     (literal_dictionary (literal_key) @font-lock-constant-face)
     ((scoped_identifier
       (scope) @_scope
       (identifier) @font-lock-constant-face
       (:match "\\(?:true\\|false\\)\\'" @font-lock-constant-face))))
         
   :language 'vim
   :feature 'operator
   `([(match_case) (bang) (spread) ,@vimscript-ts-mode--operators]
     @font-lock-operator-face
     (unary_operation "!" @font-lock-negation-char-face)
     (binary_operation "." @font-lock-operator-face)
     (ternary_expression ["?" ":"] @font-lock-operator-face)
     (set_item "?" @font-lock-operator-face)
     (inv_option "!" @font-lock-negation-char-face)
     (edit_statement ["#"] @font-lock-punctuation-face))

   :language 'vim
   :feature 'bracket
   '(["(" ")" "{" "}" "[" "]" "#{"] @font-lock-bracket-face)

   :language 'vim
   :feature 'delimiter
   '(["," ";" ":"] @font-lock-delimiter-face
     (field_expression "."  @font-lock-delimiter-face))

   :language 'vim
   :feature 'function
   ;; :override 'keep
   `((call_expression
      ;; XXX: how to match preceding part only of function: (identifier
      ;; (curly_brace_name)), eg. 'foo_' in foo_{{x -> x*10}}()
      function: (identifier) @font-lock-function-call-face
      "(" [(identifier)] @font-lock-variable-use-face :* ")")

     (call_expression
      function: (scoped_identifier (identifier) @font-lock-function-call-face))
     
     ((set_item
       option: (option_name) @_option
       value: (set_value) @font-lock-function-name-face)
      (:match
       ,(rx-to-string
         `(seq bos
               (or "tagfunc" "tfu"
                   "completefunc" "cfu"
                   "omnifunc" "ofu"
                   "operatorfunc" "opfunc")
               eos))
       @_option)))

   :language 'vim
   :feature 'variable
   '((identifier) @font-lock-variable-use-face)

   :language 'vim
   :feature 'assignment
   :override 'keep
   '((set_item
      option: (option_name) @font-lock-variable-name-face
      value: (set_value) @font-lock-string-face)
     (let_statement (_) @font-lock-variable-name-face)
     (env_variable (identifier) @font-lock-variable-name-face)
     (map_statement
      lhs: (map_side) @font-lock-variable-name-face
      rhs: _ @font-lock-string-face))

   ;; :language 'vim
   ;; :feature 'error
   ;; :override t
   ;; '((ERROR) @font-lock-warning-face)
   )
  "Tree-sitter font-lock settings for `vimscript-ts-mode'.")

;;; Embedded languages
;; These are: lua ruby perl python

(defvar lua-ts--font-lock-settings)
(defvar lua-ts--simple-indent-rules)
(declare-function ruby-ts--font-lock-settings "ruby-ts-mode")
(declare-function ruby-ts--indent-rules "ruby-ts-mode")

(defun vimscript-ts-mode--treesit-language-at-point (langs)
  "Create function to determine language at point using available LANGS."
  `(lambda (point)
     (let ((node (treesit-node-at point 'vim)))
       (if (or (equal (treesit-node-type node) "chunk")
               (and (equal (treesit-node-type node) "body")
                    (setq node (treesit-node-parent node))))
           (pcase (treesit-node-type (treesit-node-parent node))
             ,@(cl-loop for lang in langs
                        collect
                        `(,(concat (symbol-name lang) "_statement") ',lang))
             (_ 'vim))
         'vim))))

(defun vimscript-ts-mode--treesit-range-rules (langs)
  "Create range captures for LANGS."
  (cl-loop for lang in langs
           when (treesit-ready-p lang)
           nconc
           (let ((stmt (intern (concat (symbol-name lang) "_statement")))
                 (capture (intern (concat "@" (symbol-name lang)))))
             (treesit-range-rules
              :host 'vim
              :embed lang
              :local t
              `((,stmt
                 (script (body) ,capture))
                (,stmt (chunk) ,capture))))))

(defun vimscript-ts-mode--merge-features (a b)
  "Merge `treesit-font-lock-feature-list's A with B."
  (cl-loop for x in a
           for y in b
           collect (seq-uniq (append x y))))

;;; Navigation

(defun vimscript-ts-mode--defun-name (node)
  "Find name of NODE."
  (treesit-node-text
   (or (treesit-node-child-by-field-name node "name")
       node)))

(defvar vimscript-ts-mode--sentence-nodes nil
  "See `treesit-sentence-type-regexp' for more information.")

(defvar vimscript-ts-mode--sexp-nodes nil
  "See `treesit-sexp-type-regexp' for more information.")

(defvar vimscript-ts-mode--text-nodes
  (rx (or "comment" "string" "filename" "pattern" "heredoc"))
  "See `treesit-text-type-regexp' for more information.")

;;; Imenu

(defvar vimscript-ts-mode--imenu-settings
  `(("Function" "\\`function_declaration\\'")
    ("Command" "\\`command_statement\\'"))
  "See `treesit-simple-imenu-settings' for more information.")

;;;###autoload
(define-derived-mode vimscript-ts-mode prog-mode "Vim"
  "Major mode for vimscript buffers.

\\<vimscript-ts-mode-map>"
  :group 'vim
  :syntax-table vimscript-ts-mode--syntax-table
  (when (treesit-ready-p 'vim)
    (treesit-parser-create 'vim)

    ;; Comments
    (setq-local comment-start "\"")
    (setq-local comment-end "")
    (setq-local comment-start-skip "\"+[ \t]*")
    (setq-local parse-sexp-ignore-comments t)

    ;; Indentation
    (setq-local treesit-simple-indent-rules vimscript-ts-mode--indent-rules)

    ;; Font-Locking
    (setq-local treesit-font-lock-feature-list vimscript-ts-mode--feature-list)
    (setq-local treesit-font-lock-settings vimscript-ts-mode--font-lock-settings)
    
    ;; Navigation
    (setq-local treesit-defun-tactic 'top-level)
    (setq-local treesit-defun-name-function #'vimscript-ts-mode--defun-name)
    (setq-local treesit-defun-type-regexp (rx (or "function_definition")))
    
    ;; navigation objects
    (setq-local treesit-thing-settings
                `((vim
                   (sexp ,vimscript-ts-mode--sexp-nodes)
                   (sentence ,vimscript-ts-mode--sentence-nodes)
                   (text ,vimscript-ts-mode--text-nodes))))

    ;; Imenu
    (setq-local treesit-simple-imenu-settings vimscript-ts-mode--imenu-settings)

    ;; Embedded parsers
    (let (langs)
      (when (treesit-ready-p 'lua t)
        (require 'lua-ts-mode)
        (push 'lua langs)
        (setq-local treesit-font-lock-settings
                    (append treesit-font-lock-settings lua-ts--font-lock-settings))
        (setq-local treesit-simple-indent-rules
                    (append treesit-simple-indent-rules lua-ts--simple-indent-rules)))

      (when (treesit-ready-p 'ruby t)
        (require 'ruby-ts-mode)
        (push 'ruby langs)
        (setq-local treesit-font-lock-settings
                    (append treesit-font-lock-settings
                            (ruby-ts--font-lock-settings 'ruby)))
        (setq-local treesit-simple-indent-rules
                    (append treesit-simple-indent-rules (ruby-ts--indent-rules)))
        (setq-local treesit-font-lock-feature-list
                    (vimscript-ts-mode--merge-features
                     treesit-font-lock-feature-list
                     ;; `ruby-ts-mode' `treesit-font-lock-feature-list'
                     '(( comment method-definition parameter-definition)
                       ( keyword regexp string type)
                       ( builtin-variable builtin-constant builtin-function
                         delimiter escape-sequence
                         constant global instance
                         interpolation literal symbol assignment)
                       ( bracket function operator punctuation)))))
      (when langs
        (setq-local treesit-language-at-point-function
                    (vimscript-ts-mode--treesit-language-at-point langs))
        (setq-local treesit-range-settings
                    (vimscript-ts-mode--treesit-range-rules langs))))

    ;; Last entry in `treesit-font-lock-settings' in case embedded langs are
    ;; highlighted
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        vimscript-ts-mode--font-lock-embedded))

    (treesit-major-mode-setup)

    (setq-local syntax-propertize-function #'vimscript-ts-mode--syntax-propertize)))

(when (treesit-ready-p 'vim)
  (let ((exts (rx (or ".vim" (seq (? (or "." "_")) (? "g") "vimrc") ".exrc") eos)))
    (add-to-list 'auto-mode-alist `(,exts . vimscript-ts-mode))))

(provide 'vimscript-ts-mode)
;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:
;;; vimscript-ts-mode.el ends here
