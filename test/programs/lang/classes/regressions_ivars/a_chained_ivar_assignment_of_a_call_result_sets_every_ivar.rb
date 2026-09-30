# A chained assignment `@a = @b = expr` with a call on the right sets
# every ivar in the chain to the result, also when the ivars held
# Strings before and the result is an Integer.

class T_issue235_chain_tail_widening_C
  def initialize
    @a = "hello"
    @b = "world"
  end

  def make_int
    42
  end

  # A method call on the right, not a literal.
  def reset_call
    @a = @b = make_int
  end

  # A chain of three, with a call on the right.
  def reset_three(c)
    @a = @b = @c = c.length
  end

  def show
    puts @a
    puts @b
  end
end

c = T_issue235_chain_tail_widening_C.new
c.reset_call
c.show                  # 42 / 42

c2 = T_issue235_chain_tail_widening_C.new
c2.reset_three("ab")
c2.show                 # 2 / 2

# reset_three also sets @c, which no code reads.
puts "ok"
