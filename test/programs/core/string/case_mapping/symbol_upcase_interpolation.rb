# Symbol#upcase / #downcase on a symbol that a method returns from two
# branches, inside string interpolation. The shape comes from the
# nagiosplugin gem.
class P
  def status(n)
    return :critical if n > 2
    return :warning if n > 1
    :ok
  end
  def output(n)
    "X #{status(n).upcase}"
  end
  def lower(n)
    "y #{status(n).downcase}"
  end
end

puts P.new.output(3)
puts P.new.output(2)
puts P.new.output(1)
puts P.new.lower(3)
puts "hi".to_sym.inspect
