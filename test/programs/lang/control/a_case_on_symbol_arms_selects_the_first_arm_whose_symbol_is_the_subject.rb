# A `case` whose `when` values are all symbol literals compares the
# subject with each symbol in the order of the arms. The first equal one
# selects its arm, so a later arm with the same symbol never runs. A
# subject that equals no symbol gives the `else` body, or nil with no
# `else`. A String, an Integer or nil with the name of a symbol equals
# no symbol. The subject is evaluated one time.
def color(x)
  case x
  when :red then "warm"
  when :orange, :yellow then "warm too"
  when :blue then "cool"
  when :green, :teal, :cyan then "cool too"
  else "unknown"
  end
end

def no_else(x)
  case x
  when :a then 1
  when :b then 2
  end
end

def twice(x)
  case x
  when :dup then "first"
  when :other, :dup then "second"
  else "none"
  end
end

p %i[red orange yellow blue green teal cyan purple].map { |s| color(s) }
p ["red", "blue", 1, nil, 1.5, :Red, :"red ", Object.new].map { |s| color(s) }
p no_else(:a), no_else(:b), no_else(:c), no_else("a"), no_else(nil)
p twice(:dup), twice(:other), twice(:x)

calls = 0
next_kind = lambda do
  calls += 1
  :blue
end
p(case next_kind.call
  when :red then 1
  when :green then 2
  when :blue then 3
  end)
p calls

# A symbol made at run time is the same symbol as the literal.
name = "te" + "al"
p color(name.to_sym), color(:"#{name}")

# An arm body can be empty, or be a statement with no value.
r = case :b
    when :a then 1
    when :b
    end
p r

# A long loop keeps the same answers.
sum = 0
kinds = %i[red blue green purple orange]
50_000.times { |i| sum += color(kinds[i % kinds.size]).size }
p sum
