" chili.nvim — Neovim plugin for kdb+/q process management
" Maintainer: Jo Shinonome
" License: MIT

if exists('g:loaded_chili')
  finish
endif
let g:loaded_chili = 1

lua require('chili').setup()
