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

