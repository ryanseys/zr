# Redefinitions of the program's own methods, of accessors, of aliased
# and removed methods, and the names ruby itself depends on.
$VERBOSE = true
class Foo; def a = 1; def a = 2; attr_reader :b; def b = 3; end
class Foo; alias c a; def a = 4; end
module Kernel; def puts(*) = nil; end
class String; define_method(:+) { |x| x }; end
module Comparable; def <(o) = true; end
class Array; alias_method :my_first, :first; def first = 9; end
o = Object.new; def o.x = 1; def o.x = 2
class Integer; undef_method :succ; def succ = 1; end
class Hash; remove_method :fetch; def fetch(*) = 1; end
class Bar; def object_id = 1; def __send__(*) = 1; end
class Object; def initialize(*) = nil; end
module M; def to_s = "m"; end
class Symbol; prepend M; end
module R; refine(String) { def upcase = "r" }; end
class << Kernel; def puts(*) = nil; end
$VERBOSE = false
class Foo; def a = 5; end
class Object; def respond_to_missing?(*) = false; end
$VERBOSE = nil
class Object; def method_missing(*) = nil; end
S = Struct.new(:a)
class S; def a; end; end
Struct.new(:b).class_eval { def b; end }
D = Data.define(:c)
class D; def c; end; end
p :done
