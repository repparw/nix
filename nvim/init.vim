" Enable alignment
let g:neoformat_basic_format_align = 1

" Enable tab to space conversion
let g:neoformat_basic_format_retab = 1

" Enable trimmming of trailing whitespace
let g:neoformat_basic_format_trim = 1

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

" Splits
set splitbelow
set splitright


call plug#begin('~/.config/nvim/plugged')
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'sbdchd/neoformat'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'Luxed/ayu-vim'
call plug#end()

set termguicolors

set background=dark

colorscheme ayu
set tabstop=4
set shiftwidth=2
