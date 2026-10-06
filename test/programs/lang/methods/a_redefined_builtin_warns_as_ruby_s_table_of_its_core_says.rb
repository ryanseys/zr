# ruby warns for a redefined builtin as its own table says: with the
# <internal:*> line of a method written in Ruby, not at all for a name
# that another shares, and about four names on Object whatever else.
$VERBOSE = true
module Kernel; def tap = 1; def then = 1; def frozen? = 1; end
class Integer; def times = 1; def zero? = 1; def ceildiv(x) = 1; def to_i = 1; end
class Array; def first = 1; def sample = 1; def shuffle = 1; def pack(x) = 1; end
class String; def unpack(x) = 1; def unpack1(x) = 1; end
class Float; def to_f = 1; end
class NilClass; def to_i = 1; end
class << Time; def now = 1; def at(x) = 1; end
class Hash; def each = 1; end
module Enumerable; def map = 1; end
class Symbol; def to_sym = 1; end
class TrueClass; def to_s = "t"; end
class << Thread; def new = 1; end
class Proc; def call = 1; end
class Object; def respond_to?(*) = true; def method_missing(*) = 1; end
class Integer; def +(x) = 1; end
p :done
