let g:python_host_prog = '/usr/bin/python2'
let g:python3_host_prog = '/usr/bin/python3'
let mapleader="," " Leader key
" Added by me

" Mappings
	noremap <leader>s :update<CR>
	
	" fzf
	nnoremap <silent> <leader>o :Files<CR>
	nnoremap <silent> <leader>O :Files!<CR>
	nnoremap <silent> <F1> :Helptags<CR>

set relativenumber

augroup Fedora
  autocmd!
  " RPM spec file template
  autocmd BufNewFile *.spec silent! 0read /usr/share/nvim/template.spec
augroup END

" vim: et ts=2 sw=2
"
" Added by me

set termguicolors

set background=dark

call plug#begin('~/.config/nvim/plugged')
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'Luxed/ayu-vim'
call plug#end()
colorscheme ayu
