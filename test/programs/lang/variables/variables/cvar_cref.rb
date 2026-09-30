# frozen_string_literal: true

# `@@x` resolves against the LEXICAL cref, and only a `class`/`module`
# body opens one. Outside any of them ruby raises where the access
# stands, so a compile that cannot name an owner answers the raise rather
# than refusing the program.
#
# A name-taking macro spreads a `*` splat of a written Array, which is how
# `attr_reader(*%i[a b])` and `private(*names)` are written.

class Counted
  @@count = 0
  attr_accessor(*%i[tag note])
  def self.bump = @@count += 1
  def count = @@count
  def defined_count = defined?(@@count)
  def defined_other = defined?(@@nowhere)
end
Counted.bump
p Counted.new.count
p Counted.class_variables

# Reopening Object explicitly IS a cref, so this stores.
class Object
  @@on_object = 1
end
p Object.class_variables.include?(:@@on_object)

def raised
  yield
  "no raise"
rescue RuntimeError => e
  e.message
end

p raised { @@toplevel_read }
p raised { @@toplevel_write = 1 }
p raised { @@toplevel_op ||= 1 }
p raised { Class.new { @@in_class_new = 1 } }

# `defined?` never evaluates its operand, so it answers nil rather than
# raising -- and inside a body it asks the run time.
p defined?(@@never_assigned)
p [Counted.new.defined_count, Counted.new.defined_other]

# The right-hand side has already run by the time the raise fires.
ran = nil
p raised { @@late = (ran = :ran) }
p ran

class Visible
  def one = 1
  def two = 2
  private(*[:one, :two])
  class << self
    def hidden = :hidden
    private :hidden
    public(*%i[hidden])
  end
end
p Visible.private_instance_methods(false).sort
p Visible.hidden
