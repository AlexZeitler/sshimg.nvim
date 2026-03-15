# sshimg.nvim

Paste images from your local clipboard into remote Neovim over SSH.

## How it works

```
Screenshot (local) → imgd daemon → SSH reverse tunnel → scp → Remote Neovim
```

A small local daemon (`imgd`) reads images from your clipboard and transfers
them to the remote server via `scp` when triggered from Neovim.

## Requirements

### Local machine
- `wl-paste` (Wayland)
- `scp`
- Python 3

### Remote server
- Neovim
- Python 3 (for the tunnel client)

## Installation

### 1. Start the local daemon

```bash
python3 daemon/imgd.py
```

Or install it permanently:

```bash
cp daemon/imgd.py ~/.local/bin/imgd
chmod +x ~/.local/bin/imgd
```

### 2. Connect with a reverse tunnel

```bash
ssh -R 9999:localhost:9999 yourserver
```

Or add to `~/.ssh/config`:

```
Host yourserver
    RemoteForward 9999 localhost:9999
```

### 3. Install the Neovim plugin

```lua
return {
  "AlexZeitler/sshimg.nvim",
  config = function()
    require("sshimg").setup()
  end,
}
```

## Configuration

```lua
require("sshimg").setup({
  port = 9999,
  host = "127.0.0.1",
  keymaps = {
    assets   = "<leader>pa",  -- Save to ./assets/
    parallel = "<leader>pp",  -- Save to same dir as current file
  },
})
```

## Usage

1. Make a screenshot (lands in local clipboard)
2. Open a Markdown file in remote Neovim
3. Press `<leader>pa` or `<leader>pp`

The plugin inserts a Markdown image link at the cursor:

```markdown
![](assets/2026-03-15-23-25-25.png)
```

## Supported platforms

| Local OS        | Clipboard tool |
|-----------------|----------------|
| Linux (Wayland) | `wl-paste`     |

## License

MIT
