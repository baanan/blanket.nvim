local M = {}

local utils = require("utils")
local xml_converter = require("converters.xml")

local default_config = {
  report_path = nil,
  filetypes = nil,
  silent = true,
  signs = {
    priority = 10,
    incomplete_branch = "█",
    uncovered = "█",
    covered = "█",

    incomplete_branch_color = "WarningMsg",
    covered_color = "Statement",
    uncovered_color = "Error",

    sign_group = "Blanket",
  },
}

local buf_enter_ag = "buf_enter_auto_group"
local is_loaded = false
local file_watcher = vim.uv.new_fs_event()

ParseFile = function()
  -- ensure that the watcher is started
  file_watcher:stop()
  file_watcher:start(
    M.__user_config.report_path,
    {},
    vim.schedule_wrap(function()
      ParseFile()
      M.refresh()
    end)
  )

  -- ignore any errors
  -- local success = true
  -- local parsed = xml_converter.parse(M.__user_config.report_path)
  local success, parsed = pcall(function()
    return xml_converter.parse(M.__user_config.report_path)
  end)

  if success then
    assert(parsed ~= nil)
    print("jacoco parse succeeded")
    return parsed
  else
    print("jacoco parse didn't succeed :( " .. parsed)
    return nil
  end
end

local register_buf_enter_ag = function()
  if M.__user_config.filetypes and type(M.__user_config.filetypes) == "string" then
    vim.cmd(string.format(
      [[
            augroup %s
                autocmd!
                autocmd FileType %s :lua require'blanket'.refresh()
            augroup END
        ]],
      buf_enter_ag,
      M.__user_config.filetypes
    ))
  end
end

M.__cached_report = nil
M.__user_config = {}

local function update_signs(report)
  local buf_name = vim.api.nvim_buf_get_name(0)
  local stats = report:get(buf_name)
  if stats then
    utils.update_signs(
      stats,
      M.__user_config.signs.sign_group,
      vim.api.nvim_get_current_buf(),
      M.__user_config.signs.priority
    )
  else
    if not M.__user_config.silent then
      print("unable to locate stats for " .. buf_name)
    end
  end
end

M.refresh = function()
  if not is_loaded then
    print("please call setup")
    return
  end
  if M.__user_config.report_path == nil then
    if not M.__cached_report.silent then
      print("report path is not set!")
    end

    return
  end

  local report = ParseFile()
  if report then
    update_signs(report)
  else
    vim.fn.timer_start(1000, M.refresh)
  end
end

M.start = function()
  M.refresh()
  register_buf_enter_ag()
end

M.stop = function()
  utils.unset_all_signs(M.__user_config.signs.sign_group)
  file_watcher:stop()
  vim.cmd(string.format(
    [[
        augroup %s
            autocmd!
        augroup END
    ]],
    buf_enter_ag
  ))
end

M.set_report_path = function(report_path)
  if not is_loaded then
    print("please call setup")
    return
  end
  if report_path then
    M.__user_config.report_path = utils.expand_file_path(report_path)
    ParseFile()
  end
end

M.pick_report_path = function()
  if not is_loaded then
    print("please call setup")
    return
  end

  vim.ui.input(
    { prompt = "New report_path: ", completion = "file", default = M.__user_config.report_path },
    function(user_input)
      M.set_report_path(user_input)
    end
  )
end

M.setup = function(config)
  if is_loaded then
    return
  end

  is_loaded = true

  M.__user_config = vim.tbl_deep_extend("force", default_config, config)
  if M.__user_config.report_path == nil then
    M.__user_config.report_path = utils.expand_file_path(M.__user_config.report_path)
  end

  -- if not M.__user_config.silent then
  --   print(vim.inspect(M.__user_config))
  -- end

  vim.cmd(
    string.format(
      [[
            sign define CocCoverageUncovered text=%s texthl=%s
            sign define CocCoverageCovered text=%s texthl=%s
            sign define CocCoverageMissingBranch text=%s texthl=%s
        ]],
      M.__user_config.signs.uncovered,
      M.__user_config.signs.uncovered_color,
      M.__user_config.signs.covered,
      M.__user_config.signs.covered_color,
      M.__user_config.signs.incomplete_branch,
      M.__user_config.signs.incomplete_branch_color
    )
  )

  register_buf_enter_ag()
end

return M
