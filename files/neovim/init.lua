local function bootstrap_pckr()
  local pckr_path = vim.fn.stdpath("data") .. "/pckr/pckr.nvim"

  if not (vim.uv or vim.loop).fs_stat(pckr_path) then
    vim.fn.system({
      'git', 'clone', "--filter=blob:none",
      'https://github.com/lewis6991/pckr.nvim', pckr_path
    })
  end

  vim.opt.rtp:prepend(pckr_path)
end

bootstrap_pckr()

require('pckr').add{
  -- Appearance
  'uZer/pywal16.nvim';
  'nvim-lualine/lualine.nvim';

  -- Buffer shenanigans
  'vim-scripts/bufkill.vim';
  'vim-scripts/scratch.vim';

  -- Git
  'tpope/vim-fugitive';

  -- Project navigation
  {
    'nvim-telescope/telescope.nvim',
    requires = 'nvim-lua/plenary.nvim'
  };
  'junegunn/fzf';
  'junegunn/fzf.vim';
  'lambdalisue/fern.vim';
  'lambdalisue/vim-fern-renderer-nerdfont';

  -- Code utils;
  'tpope/vim-surround';
  'tpope/vim-commentary';
  'tpope/vim-unimpaired';
  'godlygeek/tabular';
  'preservim/tagbar';
  'tpope/vim-vinegar';
  'bfrg/vim-cpp-modern';
  {
    'nvim-treesitter/nvim-treesitter',
    run = { ':TSUpdate' }
  };

  -- Terminal
   'numToStr/FTerm.nvim';

  -- AI
  {
    'yetone/avante.nvim',
    branch = 'main',
    requires = {
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'MeanderingProgrammer/render-markdown.nvim',

      'nvim-tree/nvim-web-devicons',
      'HakonHarnes/img-clip.nvim',
      'zbirenbaum/copilot.lua',
    },
    run = 'make',
    config = function()
      require('avante').setup()
    end
  }
}

local lualine = require('lualine')
local diagnostics = {
	"diagnostics",
	sources = { "nvim_diagnostic" },
	sections = { "error", "warn" },
	symbols = { error = " ", warn = " " },
	colored = true,
	update_in_insert = false,
	always_visible = true,
	cond = function()
		return vim.bo.filetype ~= "markdown"
	end,
}

local diff = {
	"diff",
	colored = true,
	symbols = { added = " ", modified = " ", removed = " " },
}

local mode = {
	"mode",
	fmt = function(str)
		return "-- " .. str .. " --"
	end,
}

local branch = {
	"branch",
	icon = "",
}

local progress = function()
	local current_line = vim.fn.line(".")
	local total_lines = vim.fn.line("$")
	local chars = { "", "", "" } --adding more chars will still work
	local line_ratio = current_line / total_lines
	local index = math.ceil(line_ratio * #chars)
	return chars[index] .. " " .. math.floor(line_ratio * 100) .. "%%"
end

lualine.setup({
options = {
	icons_enabled = true,
	theme = "auto",
	component_separators = { left = "", right = "" },
	section_separators = { left = "", right = "" },
	disabled_filetypes = { "alpha", "dashboard" },
	always_divide_middle = true,
	},

sections = {
	lualine_a = { branch },
	lualine_b = { mode },
	lualine_c = { diagnostics },
	lualine_x = { diff, "fileformat", "filetype" },
	lualine_y = { "location" },
	lualine_z = { progress },
	},
})

require("lualine").setup()
require("pywal16").setup()

local map = vim.keymap.set

map("n", "<Space>", "<Nop>", { silent = true, remap = false })
vim.g.mapleader = " "

vim.g.ruby_indent_assignment_style = 'variable'

-- Some basic options
vim.opt.clipboard = 'unnamedplus'
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.number = true

vim.opt.termguicolors = true
vim.opt.rtp:append("/opt/homebrew/opt/fzf")

vim.opt.backspace = "indent,eol,start"
vim.opt.isk:append("$,@,%,#")
vim.opt.showcmd = true
vim.opt.hidden = true

vim.opt.laststatus = 2
vim.opt.relativenumber = true

vim.opt.mouse = a

vim.opt.colorcolumn = "81"

vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true

vim.opt.scrolloff = 5

vim.opt.tags:prepend(".git/tags")

vim.opt.wildmode="longest,list,full"
vim.opt.wildignore:append("*.o,*.pyc,*.obj,*.rbc,*.class")
vim.opt.wildignore:append(".git,.svn,vendor/gems/*,bundle,_html,env,tmp")
vim.opt.wildignore:append("node_modules,public/uploades,public/assets")
vim.opt.wildignore:append("public/assets/source_maps")

vim.lsp.set_log_level("DEBUG")

vim.lsp.config["clangd"] = {
  cmd = { 
    "clangd",
    "--header-insertion=never",
    "--all-scopes-completion",
    "--background-index"
  },
  filetypes = { 'c', 'cpp', 'h', 'hpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = {
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac', -- AutoTools
    '.git',
  },
  capabilities = {
    textDocument = {
      completion = {
        editsNearCursor = true,
      },
    },
    offsetEncoding = { 'utf-8', 'utf-16' },
  }
}
vim.lsp.enable("clangd")

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

augroup("c_shenanigans", {})
augroup("ruby_shenanigans", {})

autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.c,*.h",
  group = 'c_shenanigans',
  callback = function()
    vim.opt.filetype = "c"
    vim.opt.tabstop = 8
    vim.opt.shiftwidth = 4
    vim.opt.smarttab = true
    vim.opt.expandtab = true
  end
})

autocmd({"BufRead"}, {
  pattern = "**/ruby/**/*.c",
  group = "ruby_shenanigans",
  callback = function() 
    vim.opt_local.cinoptions = ":2,=2,l1"
  end
})

autocmd({"BufRead", "BufNewFile"}, {
  pattern = "Gemfile,Rakefile,Capfile,*.rake",
  group = "ruby_shenanigans",
  callback = function()
    vim.opts.filetype = "ruby"
  end
})

autocmd({"BufRead", "BufNewFile"}, {
  pattern = "*.rb",
  group = "ruby_shenanigans",
  callback = function()
    vim.cmd("hi def Tab ctermbg=red guibg=red")
    vim.cmd("hi def TrailingWS ctermbg=red guibg=red")
    vim.cmd("hi def rubyStringDelimiter ctermbg=NONE")
    map("", "<Ctrl>-s", ":!ruby -cw %<cr>")
  end
})
  
local telescope = require('telescope.builtin')
vim.keymap.set('n', '<leader>f', telescope.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>o', telescope.buffers, { desc = 'Telescope buffers' })
vim.keymap.set('n', '<leader>t', telescope.current_buffer_tags, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>T', telescope.tags, { desc = 'Telescope help tags' })

map("", "<C-h>", "<C-w>h")
map("", "<C-j>", "<C-w>j")
map("", "<C-k>", "<C-w>k")
map("", "<C-l>", "<C-w>l")

function taggit()
  os.execute[[
    ctags --tag-relative=yes \
          --extras=+f \
          --languages=-javascript,sql,TypeScript
          --exclude=.ext
          -Rf.git/tags]]
end

map("", "<Leader>rt", taggit)
