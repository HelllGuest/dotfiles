-- lua/config/options.lua
local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.colorcolumn = "100"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false
opt.linebreak = true
opt.showmode = false
opt.termguicolors = true
opt.laststatus = 3
opt.cmdheight = 0
opt.pumheight = 12
opt.pumblend = 10
opt.winblend = 10
opt.conceallevel = 2
opt.fillchars = {
  foldopen = " ",
  foldclose = " ",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}

opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.shiftround = true
opt.autoindent = true
opt.smartindent = true

opt.clipboard = "unnamedplus"
opt.undofile = true
opt.undolevels = 10000
opt.updatetime = 200
opt.timeoutlen = 300

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
opt.grepprg = "rg --vimgrep --smart-case"
opt.grepformat = "%f:%l:%c:%m"

opt.splitbelow = true
opt.splitright = true
opt.splitkeep = "screen"

opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.foldcolumn = "1"

opt.fileencoding = "utf-8"
opt.autowrite = true
opt.confirm = true
opt.backup = false
opt.swapfile = false
opt.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

opt.completeopt = { "menu", "menuone", "noselect" }
opt.wildmode = "longest:full,full"

opt.diffopt:append("linematch:60")

opt.spell = false
opt.spelllang = { "en_us" }

opt.lazyredraw = false
opt.synmaxcol = 300
opt.redrawtime = 1500

if vim.g.neovide then
  vim.g.neovide_cursor_animation_length = 0
  vim.g.neovide_scroll_animation_length = 0.3
end
