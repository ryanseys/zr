# detailed_message shows the line an error came from with a caret run
# under the node that failed, as error_highlight spots it: a call's name
# or arguments, a constant, an operator write, and for a wrong argument
# count both the caller and the callee. did_you_mean adds its guess.

def show
  yield
rescue Exception => e
  puts e.detailed_message(highlight: false), "--"
end
def two(a, b) = a
def kw(a:) = a
x = nil
show { x.lenght }
show { x&.foo.bar }
show { 1 + nil }
show { Integer("zz") }
show { [1, 2].first("a") }
show { two(1) }
show { kw }
show { UndefinedThing }
show { Comparable::Nope }
show { foo_bar_baz }
show { x.foo = 1 }
show { h = nil; h[:a] += 1 }
show { a = nil; a += 1 }
show { ->(a) {}.call }
show { {a: 1}.fetch(:b) }
show { "abc".unknown_meth(1, 2) }
show { lengthh = 1; lenghth }
show { [1].frist }

