# Under a true $VERBOSE or Warning[:strict_unused_block], a block passed
# to a method that never uses it warns once, with the caller's line and
# the def's place. yield, a block parameter, super and initialize use it.
def quiet = 1
quiet { }
$VERBOSE = true
def m = 42
m { }
m { }
class Foo; def k = 1; def self.s = 2; def y = yield; def g = block_given?; def initialize; end; end
Foo.new.k { }
Foo.s { }
Foo.new.y { }
Foo.new.g { }
Foo.new { }
o = Object.new; def o.z = 1; o.z {}
def l; [1].each { }; end; l {}
def b(&) = 1
b { }
def each = 1
each { }
def n = 1
$VERBOSE = false
n { }
Warning[:strict_unused_block] = true
def q = 1
q { }
