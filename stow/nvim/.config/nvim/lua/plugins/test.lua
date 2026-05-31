-- ============================================================
-- lua/plugins/test.lua
-- neotest — JS/TS (vitest), Go, Python (pytest), Rust (cargo)
-- ============================================================
return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-go",
      "nvim-neotest/neotest-python",
      "rouge8/neotest-rust",
    },
    keys = {
      { "<leader>tt", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run file tests" },
      { "<leader>tT", function() require("neotest").run.run(vim.loop.cwd()) end,     desc = "Run all tests" },
      { "<leader>tr", function() require("neotest").run.run() end,                  desc = "Run nearest test" },
      { "<leader>ts", function() require("neotest").summary.toggle() end,            desc = "Test summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Test output" },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end,       desc = "Test output panel" },
      { "<leader>tS", function() require("neotest").run.stop() end,                  desc = "Stop test" },
      { "[T",         function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Prev failed test" },
      { "]T",         function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next failed test" },
    },
    opts = function()
      local vitest_cmd = "npx vitest"
      if vim.fn.executable("pnpm") == 1 then
        vitest_cmd = "pnpm vitest"
      elseif vim.fn.executable("npm") == 1 then
        vitest_cmd = "npm exec vitest"
      end
      return {
        adapters = {
          require("neotest-vitest")({
            vitestCommand = vitest_cmd,
          }),
          require("neotest-go")({
            experimental = { test_table = true },
          }),
          require("neotest-python")({
            dap           = { justMyCode = false },
            runner        = "pytest",
            python        = ".venv/bin/python",
          }),
          require("neotest-rust")({
            args = { "--no-capture" },
          }),
        },
        status       = { virtual_text = true },
        output       = { open_on_run = true },
        quickfix     = { open = function()
          require("trouble").open({ mode = "quickfix", focus = false })
        end },
      }
    end,
  },
}
