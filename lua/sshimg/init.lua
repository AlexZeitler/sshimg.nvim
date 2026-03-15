-- sshimg.nvim
-- Paste images from local clipboard into remote Neovim over SSH tunnel
-- https://github.com/AlexZeitler/sshimg.nvim

local M = {}

local defaults = {
  port = 9999,
  host = "127.0.0.1",
  keymaps = {
    assets = "<leader>pa",
    parallel = "<leader>pp",
  },
}

local config = {}

local function get_remote_host()
  local ssh = vim.env.SSH_CONNECTION
  if not ssh then
    return nil, "Not connected via SSH"
  end
  local handle = io.popen("hostname")
  if not handle then
    return nil, "Could not get hostname"
  end
  local hostname = handle:read("*l")
  handle:close()
  return hostname, nil
end

local function make_filename()
  return os.date("%Y-%m-%d-%H-%M-%S") .. ".png"
end

local function request_paste(remote_host, remote_path, callback)
  local cmd = string.format(
    [[python3 -c "
import socket, json
try:
    s = socket.socket()
    s.settimeout(10)
    s.connect(('%s', %d))
    req = json.dumps({'host': '%s', 'path': '%s'}) + '\n'
    s.sendall(req.encode())
    resp = s.recv(4096).decode()
    s.close()
    print(resp)
except Exception as e:
    print(json.dumps({'ok': False, 'error': str(e)}))
"]],
    config.host, config.port, remote_host, remote_path
  )

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 then return end
      local line = data[1]
      if not line or line == "" then return end
      local ok, result = pcall(vim.json.decode, line)
      if ok then
        callback(result)
      else
        callback({ ok = false, error = "Invalid response: " .. line })
      end
    end,
    on_stderr = function(_, data)
      if data and data[1] and data[1] ~= "" then
        callback({ ok = false, error = table.concat(data, "\n") })
      end
    end,
  })
end

local function insert_markdown_link(rel_path)
  local line = string.format("![](%s)", rel_path)
  vim.api.nvim_put({ line }, "l", true, true)
end

local function paste_image(dir_type)
  local remote_host, err = get_remote_host()
  if not remote_host then
    vim.notify("sshimg: " .. err, vim.log.levels.ERROR)
    return
  end

  local bufpath = vim.api.nvim_buf_get_name(0)
  if bufpath == "" then
    vim.notify("sshimg: Save the file first", vim.log.levels.ERROR)
    return
  end

  local file_dir = vim.fn.fnamemodify(bufpath, ":h")
  local filename = make_filename()
  local remote_dir, rel_path

  if dir_type == "assets" then
    remote_dir = file_dir .. "/assets"
    rel_path = "assets/" .. filename
  else
    remote_dir = file_dir
    rel_path = filename
  end

  vim.fn.jobstart({ "mkdir", "-p", remote_dir }, {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("sshimg: Could not create directory " .. remote_dir, vim.log.levels.ERROR)
        return
      end

      local remote_path = remote_dir .. "/" .. filename
      vim.notify("sshimg: Transferring image...", vim.log.levels.INFO)

      request_paste(remote_host, remote_path, function(result)
        vim.schedule(function()
          if result.ok then
            insert_markdown_link(rel_path)
            vim.notify("sshimg: Inserted " .. rel_path, vim.log.levels.INFO)
          else
            vim.notify("sshimg: Error – " .. (result.error or "unknown"), vim.log.levels.ERROR)
          end
        end)
      end)
    end,
  })
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})

  if config.keymaps.assets then
    vim.keymap.set("n", config.keymaps.assets, function()
      paste_image("assets")
    end, { desc = "sshimg: Paste image → assets/" })
  end

  if config.keymaps.parallel then
    vim.keymap.set("n", config.keymaps.parallel, function()
      paste_image("parallel")
    end, { desc = "sshimg: Paste image → same dir" })
  end
end

return M
