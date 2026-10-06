# A `case` on symbol arms compares by identity only while Symbol#=== is
# ruby's own. After the program redefines it, each `when` value gets
# the call, in the order of the arms, with the subject as argument.
def pick(x)
  case x
  when :one then 1
  when :two, :three then 23
  else 0
  end
end

p [:one, :two, :three, :four, "one"].map { |x| pick(x) }

class Symbol
  def ===(other)
    puts "#{inspect} === #{other.inspect}"
    to_s == other.to_s
  end
end

p pick("three")
p pick(:one)
p pick(:four)
