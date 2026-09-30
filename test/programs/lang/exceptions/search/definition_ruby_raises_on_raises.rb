# A `class Foo` after `module Foo`, and a reopen that names a different
# superclass, are both TypeError in ruby -- a real exception at the definition,
# not a broken program. So the program compiles, and the TypeError raises at
# run time, also when no `rescue` is visible in the definition's own statement.
#
# A CALLER can wrap the `require` in a handler that catches these. The shape
# below -- a top-level kind collision -- is in every `hola_*` tutorial gem on
# rubygems, and in a whole family of generated SDKs that declare one class
# name under two superclasses.
#
# Both halves of the message are ruby's, including the second line, whose
# position is the one stamped when the CONSTANT was created.

module Foo
  X = 1
end

begin
  class Foo
    def never = "unreachable"
  end
rescue TypeError => e
  puts e.message
end

# The definition that raised changed nothing: ruby leaves the module exactly
# as it was.
p Foo::X
p Foo.instance_of?(Module)
p Foo.respond_to?(:never)

class Base; end
class Other; end
class Sub < Base; end

begin
  class Sub < Other; end
rescue TypeError => e
  puts e.message
end

p Sub.superclass
