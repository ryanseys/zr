# The documented precedence: `-I` roots are searched in order, first hit
# wins (Ruby's own `$LOAD_PATH` rule) -- so a user root placed BEFORE the
# stdlib checkout shadows the stdlib copy of a same-named feature, and the
# later root's file is never loaded.

$LOAD_PATH.unshift(File.expand_path("earlier_root/userlib", __dir__))
$LOAD_PATH.unshift(File.expand_path("earlier_root/stdliblib", __dir__))
require_relative "earlier_root/main"
