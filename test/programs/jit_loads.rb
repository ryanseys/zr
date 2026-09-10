# native only
# The loader, in whichever process runs it: a function assembled here,
# written into a mapping of this process, and called. Under ruby the
# system half is Fiddle; in a compiled program it is the runtime's own.
require_relative "../../lib/ze0/ir/arm64"
require_relative "../../lib/ze0/obj/jit"

CLIF = <<~TEXT
  function %answer() -> i64 system_v {
  block0:
    v0 = iconst.i64 40
    v1 = iconst.i64 2
    v2 = iadd v0, v1
    return v2
  }
TEXT

functions = Ze0::IR::ClifText.parse(CLIF)
unit = Ze0::Obj::Unit.new
functions.each { |f| unit.functions << Ze0::IR::Arm64.new(f, defined: functions.map(&:name)).compile }
p unit.functions.map { |f| [f.name, f.bytes.bytesize] }

host = Ze0::Obj::JIT.host
symbols = Ze0::Obj::JIT.load(unit, host: host)
p symbols.keys
p host.call(symbols.fetch("answer"))
