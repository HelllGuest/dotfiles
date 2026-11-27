-- ~/.config/nvim/init.lua

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local uv = vim.uv or vim.loop
if not uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("config.options")
require("config.keymaps")
require("config.autocmds")

require("lazy").setup("plugins", {
  defaults = { lazy = true },
  install = { colorscheme = { "rice_gruvbox", "habamax" } },
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "matchit", "matchparen", "netrwPlugin",
        "rplugin", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded",
  },
})

-- rice-theme writes XDG_STATE_HOME/dotfiles/theme/nvim (rice_gruvbox|rice_secops).
-- Missing/invalid → habamax. No plugin theme deps.
do
  local state_home = os.getenv("XDG_STATE_HOME")
  if not state_home or state_home == "" then
    state_home = vim.fn.expand("~/.local/state")
  end
  local path = state_home .. "/dotfiles/theme/nvim"
  local name = "habamax"
  local f = io.open(path, "r")
  if f then
    local line = f:read("*l")
    f:close()
    if line and line:match("^[%w_]+$") then
      name = line
    end
  end
  pcall(vim.cmd.colorscheme, name)
end
