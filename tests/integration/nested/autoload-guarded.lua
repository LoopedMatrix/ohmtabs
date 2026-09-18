dofile(os.getenv("OHMTABS_NESTED_BASE"))
-- Exactly the hook `ohmtabs autoload enable` installs, pointed at this checkout
-- through OHMTABS_SO / OHMTABS_STATE_DIR (both honoured by native/autoload.lua).
pcall(dofile, os.getenv("OHMTABS_AUTOLOAD_LUA"))
