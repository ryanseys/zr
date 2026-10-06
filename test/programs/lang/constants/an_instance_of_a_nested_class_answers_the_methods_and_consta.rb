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

item = Store::Item.new("pen", 10)
p item.name
p item.kind
puts item
p Store.build("cup", 8).price
p Store::Discounted.new("hat", 20).price
p Store::Discounted.superclass
p Store::Format.join(["a", "b"])

