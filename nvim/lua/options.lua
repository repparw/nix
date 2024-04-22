local options = {
  splitbelow = true,
  splitright = true,
  termguicolors = true,
  ignorecase = true,
  smartcase = true,
  tabstop = 4,
  shiftwidth = 2,
  number = true,
  relativenumber = true,
  list = true,
  listchars = { tab = '» ', trail = '·', nbsp = '␣' },
  scrolloff = 10,
  inccommand = "split",
  background = "dark",
  showmode = false,
}

for k,v in pairs(options) do
  vim.opt[k] = v
end
