# Under $VERBOSE true a definition over a method warns as
# rb_method_entry_make does: not over an alias, an undef, a copy a
# visibility verb made, or the same definition again.

$VERBOSE = true
class A
  def m; end
  def m; end
  def n; end
  alias o n
  def n; end
  def o; end
  attr_accessor :x
  attr_accessor :x
  define_method(:d) {}
  define_method(:d) {}
  def d; end
  def u; end
  undef u
  def u; end
  def v; end
  remove_method :v
  def v; end
  def self.s; end
  def self.s; end
  private def p1; end
  private :p1
  public
  def p1; end
end
class B < A
  private :m
  def m; end
end
class String
  def upcase; end
end
module Kernel
  def puts(*); end
end
$VERBOSE = false
class A
  def m; end
end
$VERBOSE = nil
class A
  def m; end
end
o = Object.new
$VERBOSE = true
def o.q; end
def o.q; end
Struct.new(:a).class_eval { def a; end }

