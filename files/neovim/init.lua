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
    {
      'saghen/blink.cmp',
      run = "cargo build --release",
      config = function()
        require('blink.cmp').setup({
          appearance = {
            nerd_font_variant = 'mono'
          },
          keymap = { preset = 'super-tab' },
          completion = { documentation = { auto_show = false } },
          fuzzy = { implemetation = "rust" },
        })
      end
    };

    -- Terminal
    'numToStr/FTerm.nvim';

    -- Debugging
    {
        'rcarriga/nvim-dap-ui',
        requires = {
            'mfussenegger/nvim-dap',
            'nvim-neotest/nvim-nio',
        },
        config = function()
            require('dapui').setup()
        end
    };


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
    };
    
    {
        'coder/claudecode.nvim',
        requires = {
          'folke/snacks.nvim',
        },
        config = function()
          require('claudecode').setup()
        end
    };

    { 
      "chrisgrieser/nvim-dr-lsp",
      config = function() 
        require("dr-lsp").setup() 
      end,
    };
}

local dap, dapui = require('dap'), require('dapui')
dap.set_log_level('TRACE')

dap.adapters.lldb = {
    type = 'executable',
    command = 'lldb-dap',
    name = 'lldb'
}

dap.configurations.cpp = {
    {
        name = "protobuf-ruby",
        type = "lldb",
        request = "launch",
        program = vim.fn.expand("~/.rubies/ruby-3.4.4/bin/ruby"),
        cwd = vim.fn.expand("~/workspaces/protobuf-ruby/folders/protobuf/ruby"),
        stopOnEntry = true,
        args = { "-Ilib", vim.fn.expand("~/workspaces/protobuf-ruby/folders/resources/test.rb")},
        runInTerminal = false
    }
}

dap.configurations.c = dap.configurations.cpp


dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
    dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
    dapui.close()
end

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
        lualine_c = { diagnostics, {"filename"} },
        lualine_x = { diff, "fileformat", "filetype" },
        lualine_y = { "location" },
        lualine_z = { progress },
    },
})

require("lualine").setup()
require("pywal16").setup()

vim.g['fern#renderer'] = 'nerdfont'

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

vim.opt.signcolumn = 'no'

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

vim.lsp.set_log_level(vim.log.levels.OFF)
vim.lsp.log.set_format_func(vim.inspect)

vim.lsp.config["clangd"] = {
    cmd = { 
        "clangd",
        "--header-insertion=never",
        "--all-scopes-completion",
        "--background-index"
    },
    filetypes = { 'c', 'cpp', 'h', 'hpp', 'objc', 'objcpp', 'cuda', 'proto' },
    root_markers = {
        'Rakefile',
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
vim.lsp.config['ruby_lsp'] = {
    cmd = { 'ruby-lsp' },
    filetypes = { 'ruby', 'eruby' },
    root_markers = { 'Gemfile', '.git' },
    init_options = {
        formatter = 'none',
        initializationOptions = {
            enabledFeatures = {
                semanticHighlighting =  false
            }
        }
    },
}
vim.lsp.config['sorbet'] = {
  cmd = { 'srb', 'tc', '--lsp' },
  filetypes = { 'ruby' },
  root_markers = { 'Gemfile', '.git' },
}
vim.lsp.enable("clangd")
vim.lsp.enable("sorbet")
vim.lsp.enable("ruby_lsp")

local function add_ruby_deps_command(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "ShowRubyDeps", function(opts)
    local params = vim.lsp.util.make_text_document_params()
    local showAll = opts.args == "all"

    client.request("rubyLsp/workspace/dependencies", params, function(error, result)
      if error then
        print("Error showing deps: " .. error)
        return
      end

      local qf_list = {}
      for _, item in ipairs(result) do
        if showAll or item.dependency then
          table.insert(qf_list, {
            text = string.format("%s (%s) - %s", item.name, item.version, item.dependency),
            filename = item.path
          })
        end
      end

      vim.fn.setqflist(qf_list)
      vim.cmd('copen')
    end, bufnr)
  end,
  {nargs = "?", complete = function() return {"all"} end})
end

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

map('n', 'gD',         vim.lsp.buf.declaration)
map('n', 'gd',         vim.lsp.buf.definition)
map('n', 'K' ,         vim.lsp.buf.hover)
map('n', 'gr',         vim.lsp.buf.references)
map('n', 'gs',         vim.lsp.buf.signature_help)
map('n', 'gi',         vim.lsp.buf.implementation)
map('n', 'gt',         vim.lsp.buf.type_definition)
map('n', '<leader>gw', vim.lsp.buf.document_symbol)
map('n', '<leader>gW', vim.lsp.buf.workspace_symbol)
-- map('n', '<leader>ah', vim.lsp.buf.hover)
-- map('n', '<leader>af', vim.lsp.buf.code_action)
-- map('n', '<leader>ee', vim.lsp.util.show_line_diagnostics)
-- map('n', '<leader>ar', vim.lsp.buf.rename)
-- map('n', '<leader>=',  vim.lsp.buf.formatting)
-- map('n', '<leader>ai', vim.lsp.buf.incoming_calls)
-- map('n', '<leader>ao', vim.lsp.buf.outgoing_calls)

map('n', '<leader>ac', '<cmd>ClaudeCode<cr>', { desc = 'Toggle Claude Code' })
map('v', '<leader>as', '<cmd>ClaudeCodeSend<cr>', { desc = 'Send to Claude Code' })

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

map('n', '<C-a>', '^', { noremap = true })
map('n', '<C-e>', '$', { noremap = true })

local telescope = require('telescope.builtin')
map('n', '<leader>f', telescope.find_files, { desc = 'Telescope find files' })
map('n', '<leader>o', telescope.buffers, { desc = 'Telescope buffers' })
map('n', '<leader>t', telescope.lsp_document_symbols, { desc = 'Telescope live grep' })
map('n', '<leader>T', telescope.lsp_workspace_symbols, { desc = 'Telescope help tags' })

map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

map('n', '<leader>n', function ()
    vim.cmd('Fern . -drawer -toggle -reveal=%')
end)

function taggit()
    os.execute[[
    ctags --tag-relative=yes \
    --extras=+f \
    --languages=-javascript,sql,TypeScript
    --exclude=.ext
    -Rf.git/tags]]
end

map("", "<Leader>rt", taggit)
