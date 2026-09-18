dofile(os.getenv("OHMTABS_NESTED_BASE"))
-- Corrected autoload: hl.plugin.load only DECLARES the plugin for this config
-- evaluation. The declared set is diffed against loaded plugins after every
-- reload, so it must be identical on every evaluation (see docs/AUTOLOAD.md).
do
  local so = os.getenv("OHMTABS_SO")
  local f = io.open(so, "r")
  if f then f:close(); hl.plugin.load(so) end
end
