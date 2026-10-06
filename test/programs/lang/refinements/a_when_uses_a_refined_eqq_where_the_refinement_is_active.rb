module LooseSymbols
  refine Symbol do
    def ===(other) = other.to_s == to_s || super
  end
end

module EvenRange
  refine Range do
    def ===(other) = other.is_a?(Integer) && other.even? && super
  end
end

def plain(x)
  case x
  when :red then "red"
  else "other"
  end
end

using LooseSymbols
using EvenRange

def loose(x)
  case x
  when :red then "red"
  when :blue, :green then "cool"
  else "other"
  end
end

def even(n)
  case n
  when 1..10 then "small even"
  else "not"
  end
end

p loose(:red)
p loose("red")
p loose("green")
p loose(:yellow)
p plain("red")
p even(4)
p even(3)
p even(12)
