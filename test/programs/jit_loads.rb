# native only
# The loader, in whichever process runs it: a function assembled here,
# written into a mapping of this process, and called. Under ruby the
# system half is Fiddle; in a compiled program it is the runtime's own.
require_relative "../../lib/ze0/ir"
require_relative "../../lib/ze0/backend/aarch64/codegen"
require_relative "../../lib/ze0/obj/jit"

answer = Ze0::IR::Function.new("answer", [], "i64")
answer.ret(answer.iadd(answer.iconst("i64", 40), answer.iconst("i64", 2)))

functions = [answer]
unit = Ze0::Obj::Unit.new
functions.each { |f| unit.functions << Ze0::Backend::Aarch64::Codegen.new(f, defined: functions.map(&:name)).compile }
p unit.functions.map { |f| [f.name, f.bytes.bytesize] }

host = Ze0::Obj::JIT.host
symbols = Ze0::Obj::JIT.load(unit, host: host)
p symbols.keys
p host.call(symbols.fetch("answer"))
