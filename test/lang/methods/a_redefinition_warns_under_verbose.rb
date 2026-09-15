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

__END__
#@ stderr
lang/methods/a_redefinition_warns_under_verbose.rb:8: warning: method redefined; discarding old m
lang/methods/a_redefinition_warns_under_verbose.rb:7: warning: previous definition of m was here
lang/methods/a_redefinition_warns_under_verbose.rb:14: warning: method redefined; discarding old x
lang/methods/a_redefinition_warns_under_verbose.rb:14: warning: method redefined; discarding old x=
lang/methods/a_redefinition_warns_under_verbose.rb:16: warning: method redefined; discarding old d
lang/methods/a_redefinition_warns_under_verbose.rb:15: warning: previous definition of d was here
lang/methods/a_redefinition_warns_under_verbose.rb:17: warning: method redefined; discarding old d
lang/methods/a_redefinition_warns_under_verbose.rb:16: warning: previous definition of d was here
lang/methods/a_redefinition_warns_under_verbose.rb:25: warning: method redefined; discarding old s
lang/methods/a_redefinition_warns_under_verbose.rb:24: warning: previous definition of s was here
lang/methods/a_redefinition_warns_under_verbose.rb:29: warning: method redefined; discarding old p1
lang/methods/a_redefinition_warns_under_verbose.rb:26: warning: previous definition of p1 was here
lang/methods/a_redefinition_warns_under_verbose.rb:36: warning: method redefined; discarding old upcase
lang/methods/a_redefinition_warns_under_verbose.rb:39: warning: method redefined; discarding old puts
lang/methods/a_redefinition_warns_under_verbose.rb:52: warning: method redefined; discarding old q
lang/methods/a_redefinition_warns_under_verbose.rb:51: warning: previous definition of q was here
lang/methods/a_redefinition_warns_under_verbose.rb:53: warning: method redefined; discarding old a
