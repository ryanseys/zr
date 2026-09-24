# The compiler reads its kernel description from runtime/ext.
# The compiler runs inside the program it compiled: prism parses a string
# of ruby, the HIR builder lowers it, and the zr lowering turns it into IR
# functions over the kernel description the program carries.

require_relative "../../lib/zr/hir"
require_relative "../../lib/zr/lower"
require_relative "../../runtime/ext/os/darwin/zr_description"

desc = Zr::Machine::Description.parse(Zr::Machine::Description::KERNEL)
# Counts change with every kernel change, so the program prints only that
# each table has rows.
puts [desc.defs, desc.consts, desc.structs].map(&:any?).inspect
puts desc.def_for("zr_ary_new").ret
puts desc.const_for("QNIL")

hir = Zr::Hir.build("def twice(n) = n * 2\nputs twice(21)", "(eval)")
puts hir.locals.inspect
functions, data = Zr::Lower.new(hir, desc, Zr::Machine::Symbols.new, entry: "zr_eval_1").run
puts functions.map(&:name).inspect
puts functions.all? { |f| f.blocks.any? }
puts data.any?
__END__
[true, true, true]
Value
8
[]
["zr_eval_1_def_1_twice", "zr_eval_1"]
true
true
