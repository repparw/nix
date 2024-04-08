" Enable alignment
let g:neoformat_basic_format_align = 1

" Enable tab to space conversion
let g:neoformat_basic_format_retab = 1

" Enable trimmming of trailing whitespace
let g:neoformat_basic_format_trim = 1

let g:python_host_prog = '/usr/bin/python2'
let g:python3_host_prog = '/usr/bin/python3'
let mapleader=" " " Leader key
"--------Added by me

" Mappings
	noremap <leader>s :update<CR>
	
	" fzf
	nnoremap <silent> <leader>o :Files<CR>
	nnoremap <silent> <leader>O :Files!<CR>
	nnoremap <silent> <F1> :Helptags<CR>
" ---------
set number relativenumber

set ignorecase
set smartcase

augroup Fedora
  autocmd!
  " RPM spec file template
  autocmd BufNewFile *.spec silent! 0read /usr/share/nvim/template.spec
augroup END

" vim: et ts=2 sw=2
"
"--------Added by me

" Splits
set splitbelow
set splitright


call plug#begin('~/.config/nvim/plugged')
Plug 'junegunn/fzf'
Plug 'junegunn/fzf.vim'
Plug 'sbdchd/neoformat'
Plug 'vim-airline/vim-airline'
" Autocomplete engine, tabnine and python plugin
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-jedi'
" Auto-pair for brackets and quotes
Plug 'jiangmiao/auto-pairs'
" Tree file explorer
Plug 'preservim/nerdtree'
" Rainbow CSV
Plug 'mechatroner/rainbow_csv'
call plug#end()

let g:airline_powerline_fonts = 1

let g:deoplete#enable_at_startup = 1

inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
inoremap <expr><s-tab> pumvisible() ? "\<c-p>" : "<s-tab>"

set termguicolors

colorscheme gruvbox

" Transparent bg
highlight Normal ctermbg=NONE guibg=NONE
highlight LineNr ctermbg=NONE guibg=NONE
highlight SignColumn ctermbg=NONE guibg=NONE

set tabstop=4
set shiftwidth=2

" ---------
