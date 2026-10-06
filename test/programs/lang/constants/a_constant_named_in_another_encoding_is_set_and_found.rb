# A constant name that starts with a capital letter in its own encoding
# (ISO-8859-15, Shift_JIS, EUC-JP) is a constant name: const_set,
# const_get, defined? in an eval and remove_const all take it.
names = [
  *%W[\u{00de} \u{00c0}].flat_map { |c| [c, c.encode("iso-8859-15")] },
  "\u{1c4}", "\u{1f2}", "\u{1f88}", "\u{370}",
  *%W[\u{391} \u{ff21}].flat_map { |c| [c, c.encode("cp932"), c.encode("euc-jp")] }
]
names.each do |n|
  m = Module.new
  before = eval("defined?(m::#{n})")
  m.const_set(n, n.encoding.name)
  found = [m.const_defined?(n), eval("defined?(m::#{n})"), m.const_get(n), eval("m::#{n}")]
  m.send(:remove_const, n)
  p [n.encoding, before, *found, m.const_defined?(n)]
end
p((Module.new.const_set("\u{e0}", 1) rescue $!.class))
