-- lua/config/autocmds.lua
local au = vim.api.nvim_create_autocmd
local ag = vim.api.nvim_create_augroup

local function on_yank()
  if vim.hl and vim.hl.on_yank then
    vim.hl.on_yank({ timeout = 150 })
  elseif vim.highlight and vim.highlight.on_yank then
    vim.highlight.on_yank({ timeout = 150 })
  end
end

au("TextYankPost", {
  group = ag("highlight_yank", { clear = true }),
  callback = on_yank,
})

au("BufReadPost", {
  group = ag("restore_cursor", { clear = true }),
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

au("FileType", {
  group = ag("close_with_q", { clear = true }),
  pattern = {
    "help", "man", "qf", "lspinfo", "checkhealth",
    "notify", "gitsigns.blame", "fugitiveblame",
    "startuptime", "lazy", "mason",
  },
  callback = function(e)
    vim.bo[e.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = e.buf, silent = true })
  end,
})

au("VimResized", {
  group = ag("resize_splits", { clear = true }),
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})

au("BufWritePre", {
  group = ag("strip_whitespace", { clear = true }),
  pattern = "*",
  callback = function()
    local ft = vim.bo.filetype
    local skip = { "markdown", "text", "plaintex" }
    if not vim.tbl_contains(skip, ft) then
      vim.cmd([[%s/\s\+$//e]])
    end
  end,
})

au("FileType", {
  group = ag("filetype_settings", { clear = true }),
  pattern = { "markdown", "text", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en_us" }
  end,
})

au("FileType", {
  group = ag("filetype_settings", {}),
  pattern = { "go" },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

au("FileType", {
  group = ag("filetype_settings", {}),
  pattern = { "python" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

au("BufReadPre", {
  group = ag("large_file", { clear = true }),
  callback = function(e)
    local uv = vim.uv or vim.loop
    local ok, stat = pcall(uv.fs_stat, e.match)
    if ok and stat and stat.size > 1024 * 1024 then
      vim.b[e.buf].large_file = true
      vim.opt_local.syntax = "off"
      vim.opt_local.undofile = false
      vim.opt_local.swapfile = false
      vim.b[e.buf].miniindentscope_disable = true
    end
  end,
})

au("BufWritePre", {
  group = ag("auto_create_dir", { clear = true }),
  callback = function(e)
    if e.match:match("^%w%w+://") then
      return
    end
    local uv = vim.uv or vim.loop
    local file = uv.fs_realpath(e.match) or e.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

local function apply_palette_highlights()
  local ok, palette = pcall(require, "palette")
  if ok and palette.accent and palette.background then
    vim.api.nvim_set_hl(0, "Search", { bg = palette.accent, fg = palette.background })
  end
end

au({ "UIEnter", "ColorScheme" }, {
  group = ag("kitty_bg_fix", { clear = true }),
  callback = function()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
    if not normal.bg then
      vim.cmd("highlight Normal ctermbg=NONE guibg=NONE")
      vim.cmd("highlight NormalNC ctermbg=NONE guibg=NONE")
    end
    apply_palette_highlights()
  end,
})
