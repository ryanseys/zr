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

__END__
undefined method 'lenght' for nil (NoMethodError)

show { x.lenght }
        ^^^^^^^
--
undefined method 'bar' for nil (NoMethodError)

show { x&.foo.bar }
             ^^^^
--
nil can't be coerced into Integer (TypeError)

show { 1 + nil }
           ^^^
--
invalid value for Integer(): "zz" (ArgumentError)

show { Integer("zz") }
               ^^^^
--
no implicit conversion of String into Integer (TypeError)

show { [1, 2].first("a") }
                    ^^^
--
wrong number of arguments (given 1, expected 2) (ArgumentError)

    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:19
    | show { two(1) }
             ^^^
    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:11
    | def two(a, b) = a
          ^^^
--
missing keyword: :a (ArgumentError)

    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:20
    | show { kw }
             ^^
    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:12
    | def kw(a:) = a
          ^^
--
uninitialized constant UndefinedThing (NameError)

show { UndefinedThing }
       ^^^^^^^^^^^^^^
--
uninitialized constant Comparable::Nope (NameError)

show { Comparable::Nope }
                 ^^^^^^
--
undefined local variable or method 'foo_bar_baz' for main (NameError)

show { foo_bar_baz }
       ^^^^^^^^^^^
--
undefined method 'foo=' for nil (NoMethodError)

show { x.foo = 1 }
        ^^^^^^
--
undefined method '[]' for nil (NoMethodError)

show { h = nil; h[:a] += 1 }
                 ^^^^
--
undefined method '+' for nil (NoMethodError)

show { a = nil; a += 1 }
                  ^
--
wrong number of arguments (given 0, expected 1) (ArgumentError)

    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:27
    | show { ->(a) {}.call }
                     ^^^^^
    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:27
    | show { ->(a) {}.call }
             ^^
--
key not found: :b (KeyError)
--
undefined method 'unknown_meth' for an instance of String (NoMethodError)

show { "abc".unknown_meth(1, 2) }
            ^^^^^^^^^^^^^
--
undefined local variable or method 'lenghth' for main (NameError)

show { lengthh = 1; lenghth }
                    ^^^^^^^
Did you mean?  lengthh
--
undefined method 'frist' for an instance of Array (NoMethodError)

show { [1].frist }
          ^^^^^^
Did you mean?  first
--
