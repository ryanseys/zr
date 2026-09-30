# String, symbol, and mixed-type block params inside a spliced
# trampoline body.
#
# The block body runs at the call site of instance_exec, with each
# block param bound to the matching argument. `puts s` inside the
# body prints a String param as a String, not as an Integer.
#
# A block param shadows an outer local of the same name only
# inside the block (e.g. an outer `b = Builder.new` and a block
# param `|b|`). After the block, the outer local has its value.
#
# Tag has a subclass (TagPlus), so the example also covers a
# class with more than one kind of instance.

class Tag
  def fire(s, y, n, &b)
    instance_exec(s, y, n, &b)
  end
end

class TagPlus < Tag
end

t = Tag.new
t.fire("hi", :sym, 7) { |s, y, n| puts s; puts y; puts n }

# Block-param name shadowing an outer local: `b` (the receiver)
# vs `|b|` (the second block param). After the block, `b` must
# still be the Builder so subsequent dispatch works.
class Builder
  def initialize; @s = 0; end
  def add(n); @s = @s + n; end
  def total; @s; end
end

class BuilderPlus < Builder
end

b = Builder.new
t.fire("hi", :sym, 7) { |s, y, n| b.add(n) }   # `b` here is the outer Builder
t.fire("hi", :sym, 7) { |s, y, n| b.add(n) }

# Now actually shadow `b`: the middle block param is named `b`, so inside
# the block `b` is the :sym param (prints "sym"), not the Builder. After
# the block, `b` is the Builder again, so puts b.total below sees it.
t.fire("hi", :sym, 7) { |s, b, n| puts b }
puts b.total                     # 14

puts "done"
