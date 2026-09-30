# Typed-receiver `recv.m { ... }` &block forwarding (Site B).
#
# The literal block reaches the method's &block parameter, after the
# regular args, and `block.call` runs it.

# 1. Basic: `recv.m { ... }` with arity-0 block.call.
class App
  def run(&block)
    block.call
  end
end

App.new.run { puts "1-basic" }

# 2. block.call with one int arg, return value used.
class Doubler
  def apply(x, &block)
    block.call(x)
  end
end

puts Doubler.new.apply(21) { |n| n * 2 }

# 3. Mixed: regular arg + &block, multiple stmts in method body.
class Logger
  def log(label, &block)
    puts label
    block.call
  end
end

Logger.new.log("3-mixed") { puts "  body" }

# 4. Block invoked multiple times from inside the method.
class Repeater
  def thrice(&block)
    block.call
    block.call
    block.call
  end
end

Repeater.new.thrice { puts "4-thrice" }

# 5. Block uses interpolation of its own argument. (Closure capture
#    over outer locals is a separate subsystem — out of scope here.)
class Wrapper
  def go(n, &block)
    block.call(n)
  end
end

Wrapper.new.go(7) { |i| puts "5-arg=#{i}" }

# 6. Block returns a value used by the method.
class Picker
  def pick(&block)
    block.call(10) + block.call(20)
  end
end

puts Picker.new.pick { |n| n * 5 }

# 7. Method declares &block, call site provides none. The &block
#    parameter is nil.
class Optional
  def maybe(&block)
    puts "7-no-block"
  end
end

Optional.new.maybe

puts "done"
