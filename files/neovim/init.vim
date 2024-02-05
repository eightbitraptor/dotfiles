filetype on
filetype plugin on
filetype indent on

let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"

set termguicolors
set background=dark

set clipboard=unnamed

set autoindent " Auto-indent
set expandtab " Expand tabs to spaces
set tabstop=2
set shiftwidth=2
set number " Line numbers on
set backspace=indent,eol,start " Backspace over everything
set isk+=$,@,%,# " these aren't word dividers
set showcmd " show current command in status bar
set hidden " Allow hidden buffers
set laststatus=2
set ttimeoutlen=0 timeoutlen=1000
set relativenumber

set mouse=a

set showmode " Show modeline in status
set colorcolumn=81

set hlsearch
set ignorecase
set smartcase
set incsearch

set tags+=.git/tags

set scrolloff=5

set encoding=utf-8
set fileencoding=utf-8

set wildmode=longest:list,full
set wildignore+=*.o,*.pyc,*.obj,.git,*.rbc,*.class,.svn,vendor/gems/*,bundle,
      \_html,env,tmp,node_modules,public/uploads,public/assets/source_maps,
      \public
set suffixesadd=.rb

set nobackup
set nowb
set noswapfile

set lispwords+=module,describe,it,define-system

let g:netrw_bufsettings="noma nomod nonu nobl nowrap ro rnu"

function! MakeDirectory()
  call system('mkdir -p ' . expand('%:p:h') )
  if v:shell_error != 0
    echo "Make Directory did not return successfully"
  endif
  :w
endfunction

autocmd VimEnter                    * set vb t_vb=
autocmd BufRead,BufNewFile Makefile * set noet

augroup RubyShenanigans
  au!
  autocmd BufRead /home/mattvh/git/ruby/*.c   setlocal cinoptions=:2,=2,l1
  autocmd BufRead,BufNewFile Gemfile,Rakefile,Capfile,*.rake
        \ set filetype=ruby
  autocmd BufRead,BufNewFile *.rb
        \ hi def Tab ctermbg=red guibg=red |
        \ hi def TrailingWS ctermbg=red guibg=red |
        \ hi rubyStringDelimiter ctermbg=NONE |
        \ map <C-s> :!ruby -cw %<cr> |
        \ map <F8> :!ruby-tags
augroup END
let g:ruby_indent_assignment_style = 'variable'

augroup PythonShenanigans
  au!
  autocmd BufRead,BufNewFile *.py,*.pyw
    \ set filetype=python |
    \ set tabstop=4 shiftwidth=4 smarttab expandtab |
    \ nnoremap ;t :w\|:!nosetests %<cr>
augroup END

augroup CShenanigans
  au!
  autocmd BufRead,BufNewFile *.c,*.h
        \ set filetype=c |
        \ set tabstop=8 shiftwidth=4 smarttab expandtab |
  autocmd BufRead */ruby/*.c   setlocal cinoptions=:2,=2,l1
augroup END

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Keyboard Mapping
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let mapleader="\<Space>"

" Beginning and end of line
nnoremap <C-a> ^
nnoremap <C-e> $

" Window switching shortcuts
map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l

nnoremap <CR> :noh<CR><CR>

" Command-][ to increase/decrease indentation
vmap <D-]> >gv
vmap <D-[> <gv

" Hightlight literal Tabs
noremap <leader>w :ToggleSpaceHi<cr>

function! DoneTagging(channel)
  echo "Done tagging"
endfunction

function! Taggit()
    let job = job_start("ctags --tag-relative=yes --extras=+f -Rf.git/tags --languages=-javascript,sql,TypeScript --exclude=.ext --exclude=include/ruby-\* --exclude=rb_mjit_header.h .", { 'close_cb': 'DoneTagging'})
endfunction

" Tags
map <Leader>rt :call Taggit()<cr>

" Use fzf
nnoremap <leader>f :Files<CR>
nnoremap <leader>o :Buffers<CR>
nnoremap <leader>l :Lines<CR>
nnoremap <leader>T :Tags<CR>
nnoremap <leader>t :BTags<CR>

nnoremap <leader>n :Fern . -drawer -toggle -reveal=%<CR>
nnoremap <leader>s :TagbarToggle<CR>

" building Ruby
nnoremap <leader>m :make miniruby<cr>
nnoremap <leader>M :make<cr>
