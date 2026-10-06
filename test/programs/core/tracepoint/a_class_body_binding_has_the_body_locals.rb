# The binding of a class, module or singleton class body, as a hook
# reads it, has the locals of that body from its first event, each nil
# until it is set.
out = []
tp = TracePoint.new(:class, :line, :end) { |tp|
  next unless tp.path == __FILE__ && tp.lineno.between?(11, 25)
  b = tp.binding
  out << [tp.event, tp.lineno, b.local_variables, (b.eval("_lv") rescue $!.class), b.local_variable_defined?(:_lv)]
}
tp.enable
_lv = :top
class K
  _lv = :inside
  def m = 1
  y = 2
end
module M
  _lv = :mod
end
class << K
  _lv = :sing
  z = 3
end
tp.disable
out.each { p _1 }
