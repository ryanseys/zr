# Every verb that would change a frozen class or module says so, and
# `Regexp.allocate` answers an object with no pattern that names itself
# at the first read.
def err(label)
  print label, ": "
  p(yield)
rescue => e
  puts "#{e.class}: #{e.message}"
end

class Fz
  def a = 1
end
Fz.freeze

err("alias_method") { Fz.send(:alias_method, :b, :a) }
err("undef_method") { Fz.send(:undef_method, :a) }
err("remove_method") { Fz.send(:remove_method, :a) }
err("private") { Fz.send(:private, :a) }
err("public") { Fz.send(:public, :a) }
err("protected") { Fz.send(:protected, :a) }
err("define_method") { Fz.send(:define_method, :c) { 1 } }
err("attr_accessor") { Fz.send(:attr_accessor, :d) }
err("include") { Fz.include(Comparable) }
err("prepend") { Fz.prepend(Comparable) }
err("extend") { Fz.extend(Comparable) }
err("const_set") { Fz.const_set(:K, 1) }
err("private_constant") { Fz.send(:private_constant) }
err("class_eval") { Fz.class_eval { def z = 1 } }
err("ivar_set") { Fz.instance_variable_set(:@x, 1) }
p Fz.new.a

r = Regexp.allocate
err("source") { r.source }
err("options") { r.options }
err("to_s") { r.to_s }
err("names") { r.names }
err("match") { r.match("a") }
err("=~") { r =~ "a" }
err("==") { r == // }
p [r.frozen?, r.encoding, r.fixed_encoding?]
err("MatchData.allocate") { MatchData.allocate }
err("MatchData.new") { MatchData.new }
__END__
alias_method: FrozenError: can't modify frozen Class: Fz
undef_method: FrozenError: can't modify frozen Class: Fz
remove_method: FrozenError: can't modify frozen Class: Fz
private: FrozenError: can't modify frozen Class: Fz
public: FrozenError: can't modify frozen Class: Fz
protected: FrozenError: can't modify frozen Class: Fz
define_method: FrozenError: can't modify frozen Class: Fz
attr_accessor: FrozenError: can't modify frozen Class: Fz
include: FrozenError: can't modify frozen Class: Fz
prepend: FrozenError: can't modify frozen Class: Fz
extend: FrozenError: can't modify frozen Class: Fz
const_set: FrozenError: can't modify frozen Class: Fz
private_constant: FrozenError: can't modify frozen Class: Fz
class_eval: FrozenError: can't modify frozen Class: Fz
ivar_set: FrozenError: can't modify frozen Class: Fz
1
source: TypeError: uninitialized Regexp
options: TypeError: uninitialized Regexp
to_s: TypeError: uninitialized Regexp
names: TypeError: uninitialized Regexp
match: TypeError: uninitialized Regexp
=~: TypeError: uninitialized Regexp
==: TypeError: uninitialized Regexp
[false, #<Encoding:BINARY (ASCII-8BIT)>, false]
MatchData.allocate: NoMethodError: undefined method 'allocate' for class MatchData
MatchData.new: NoMethodError: undefined method 'new' for class MatchData
