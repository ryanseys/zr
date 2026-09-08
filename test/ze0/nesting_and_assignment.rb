module Store
  LIMIT = 3

  class Item
    KIND = "item"

    def initialize(name, price)
      @name = name
      @price = price
    end

    def name
      @name
    end

    def price
      @price
    end

    def kind
      [KIND, LIMIT]
    end

    def to_s
      "#{@name}@#{@price}"
    end
  end

  class Discounted < Item
    def price
      @price / 2
    end
  end

  module Format
    SEP = ", "

    def self.join(parts)
      parts.join(SEP)
    end
  end

  def self.build(name, price)
    Item.new(name, price)
  end
end

p Store
p Store::Item
p Store::Item::KIND
p Store::LIMIT
p Store::Item.name
p Store::Format::SEP

item = Store::Item.new("pen", 10)
p item.name
p item.kind
puts item
p Store.build("cup", 8).price
p Store::Discounted.new("hat", 20).price
p Store::Discounted.superclass
p Store::Format.join(["a", "b"])

a, b = 1, 2
p [a, b]
a, b = b, a
p [a, b]
c, d = [3, 4]
p [c, d]
e, f = 5
p [e, f]
g, *rest = [1, 2, 3, 4]
p [g, rest]
*init, last = [1, 2, 3]
p [init, last]
h, (i, j), k = 1, [2, 3], 4
p [h, i, j, k]
x, = [9, 8]
p x
$g1, $g2 = 1, 2
p [$g1, $g2]
@m, @n = 3, 4
p [@m, @n]
P1, P2 = 5, 6
p [P1, P2]
arr = [0, 0]
arr[0], arr[1] = 7, 8
p arr

def two
  [1, 2]
end
m, n = two
p [m, n]

word = /\A[a-z]+\z/
p word
p "abc".match?(word)
p "Abc".match?(word)
p "Abc".match?(/\Aa/i)
p "a-b-c".split(/-/)
p "x1y2".gsub(/\d/) { |digit| "<#{digit}>" }
p word.source

counts = {}
counts["k"] ||= 1
counts["k"] ||= 2
counts["k"] += 10
p counts

class Holder
  def initialize
    @v = nil
  end

  def v
    @v
  end

  def v=(value)
    @v = value
  end
end

hold = Holder.new
hold.v ||= "first"
hold.v ||= "second"
p hold.v
hold.v &&= "#{hold.v}!"
p hold.v
__END__
Store
Store::Item
"item"
3
"Store::Item"
", "
"pen"
["item", 3]
pen@10
8
10
Store::Item
"a, b"
[1, 2]
[2, 1]
[3, 4]
[5, nil]
[1, [2, 3, 4]]
[[1, 2], 3]
[1, 2, 3, 4]
9
[1, 2]
[3, 4]
[5, 6]
[7, 8]
[1, 2]
/\A[a-z]+\z/
true
false
true
["a", "b", "c"]
"x<1>y<2>"
"\\A[a-z]+\\z"
{"k" => 11}
"first"
"first!"
