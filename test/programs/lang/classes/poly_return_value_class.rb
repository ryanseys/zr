# A method that returns instances of two or more small classes (no
# attr_writer, no mutator), one class per branch. A call on the result
# goes to the method of the right class.

class A
  def initialize(v); @v = v; end
  def label; "A:" + @v; end
end

class B
  def initialize(v); @v = v; end
  def label; "B:" + @v; end
end

def pick(flag)
  if flag
    A.new("yes")
  else
    B.new("no")
  end
end

puts pick(true).label    # A:yes
puts pick(false).label   # B:no

# A `case`/`when` poly return — same shape, different control flow.
def by_kind(k)
  case k
  when 0 then A.new("zero")
  when 1 then B.new("one")
  else        A.new("many")
  end
end

puts by_kind(0).label    # A:zero
puts by_kind(1).label    # B:one
puts by_kind(9).label    # A:many

# Method invocation that returns a different type per class — the
# receiver dispatches to the `def`-defined method of its class.
class P
  def initialize(n); @n = n; end
  def double; @n * 2; end
end

class Q
  def initialize(n); @n = n; end
  def double; @n + 100; end
end

def numeric(flag)
  flag ? P.new(7) : Q.new(7)
end

puts numeric(true).double    # 14
puts numeric(false).double   # 107
