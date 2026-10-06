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

word = /\A[a-z]+\z/
p word
p "abc".match?(word)
p "Abc".match?(word)
p "Abc".match?(/\Aa/i)
p "a-b-c".split(/-/)
p "x1y2".gsub(/\d/) { |digit| "<#{digit}>" }
p word.source

