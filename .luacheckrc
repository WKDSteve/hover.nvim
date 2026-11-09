std = "luajit"
cache = true

-- "vim" itself is mutable (plugins assign vim.g.* freely), so it must live in
-- `globals`, not `read_globals`.
globals = {
  "vim",
}

exclude_files = {
  "TESTS/*.lua",
  -- The CI's checkouts of the dependencies: their code, their lint. testing.nvim's luacheck preset leaves them
  -- alone too, but only from 4a74733 on, and the CI runs testing.nvim at ci-verified.
  ".deps/",
  -- The hosted ubuntu leg installs luacheck through luarocks into the workspace (as in ui.nvim and sessions.nvim):
  -- luarocks' own config and rock sources are not this plugin's code.
  ".luarocks/",
}

-- Long lines are handled by stylua's column_width; don't duplicate the check.
max_line_length = false
