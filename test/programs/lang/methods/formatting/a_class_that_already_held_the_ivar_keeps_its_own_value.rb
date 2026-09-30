# A top-level `def` reaches every object, and it must answer the same five
# questions wherever it is called from.
#
# WHY THIS FILE EXISTS. zr emits a definition on Object/Kernel/BasicObject
# ONCE under its `Object#name` symbol, and ALSO materializes a private copy
# onto every user class -- 22,393 extra bodies on a program that requires
# rubygems, which is 78 MB of the binary. A builtin receiver already skips
# the copy and dispatches to the shared body (`analyze::mro` exempts it), so
# the two paths are live side by side RIGHT NOW.
#
# That makes this a decisive experiment rather than a guess: if a builtin
# receiver -- which uses the shared body -- answers exactly what a user class
# answers -- which uses its own copy -- then dropping the copy changes
# nothing. Every row below is printed for both kinds for that reason.
#
# The five questions are the ones a shared body could get wrong, because each
# is compiled from something the body would no longer own: an ivar slot, the
# caller's class, the constant cref, the method owner, and where `super`
# goes.

TOP_LEVEL_CONST = "top"

def touches_an_ivar
  @counter = (@counter || 0) + 1
  [@counter, instance_variable_get(:@counter), instance_variables]
end

def reads_a_constant
  TOP_LEVEL_CONST
end

def reports_its_owner
  method(__method__).owner
end

def calls_a_private_sibling
  a_private_helper
end

# Every top-level `def` is already a PRIVATE instance method of Object, which
# is why each row below reaches it through `send` rather than a dot.
def a_private_helper
  "private reached"
end

def goes_to_super
  super
rescue NoMethodError => e
  "no super: #{e.message[0, 24]}"
end

class Plain; end

class WithIvar
  def initialize = (@counter = 100)
end

class Overrides
  def goes_to_super = "overridden"
end

# A class that DEFINES the same name is not sharing anything, and must keep
# its own body.
class OwnCopy
  def reads_a_constant = "mine"
end

RECEIVERS = {
  # Builtin receivers: the shared-body path today.
  "String" => -> { +"s" },
  "Array" => -> { [1] },
  "Hash" => -> { {} },
  # User classes: the materialized-copy path today.
  "Plain" => -> { Plain.new },
  "WithIvar" => -> { WithIvar.new },
  "OwnCopy" => -> { OwnCopy.new },
}.freeze

def show(label, receiver)
  yield receiver
rescue StandardError => e
  "#{e.class}: #{e.message[0, 40]}"
end

# And a class that already had the ivar keeps its own value.
w = WithIvar.new
w.send(:touches_an_ivar)
puts "pre-set ivar\t#{w.instance_variable_get(:@counter)}"

