# A `case` that mixes symbol literals with other `when` values (a class,
# a range, a string, a splat, a call) sends `===` to each value in order,
# and the symbol arms keep their identity answers.
class Matcher
  def ===(other)
    puts "Matcher === #{other.inspect}"
    other == :hidden
  end
end

def kind(x)
  case x
  when :a then "sym a"
  when String then "string"
  when 1..3 then "small"
  when :b, "b" then "b"
  when Matcher.new then "matched"
  else "other"
  end
end

p [:a, "a", 2, :b, "b", :hidden, :zzz].map { |x| kind(x) }

LIST = %i[x y]
def splat(x)
  case x
  when :w then "w"
  when *LIST then "listed"
  else "no"
  end
end
p %i[w x y z].map { |x| splat(x) }

def dynamic(x, tail)
  case x
  when :pre then "pre"
  when :"pre#{tail}" then "dynamic"
  else "no"
  end
end
p dynamic(:pre, "x"), dynamic(:prex, "x"), dynamic(:prey, "x")
