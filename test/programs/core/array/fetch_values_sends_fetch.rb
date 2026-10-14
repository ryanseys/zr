# Array#fetch_values is Ruby in CRuby: it sends fetch for each index, so
# a subclass's own fetch answers. fetch takes an index and a default.
class Lenient < Array
  def fetch(index, *rest, &block)
    index.is_a?(Integer) ? super : "no #{index}"
  end
end

list = Lenient[:a, :b, :c]
p list.fetch_values(0, :x, 2)
p list.fetch_values
p [:a, :b].fetch_values(1, 0)
p [:a, :b].fetch_values(0, 5) { |i| i * 10 }

def show
  p yield
rescue IndexError, ArgumentError, TypeError => e
  p [e.class, e.message]
end

show { [:a, :b].fetch_values(0, 9) }
show { [:a, :b].fetch(1) }
show { [:a, :b].fetch(-1) }
show { [:a, :b].fetch(5, :none) }
show { [:a, :b].fetch(-5) { |i| [:block, i] } }
show { [:a, :b].fetch(9) }
show { [:a, :b].fetch }
show { [:a, :b].fetch(1, 2, 3) }
show { [:a, :b].fetch("1") }
show { [:a, :b].fetch(1.9) }
show { [:a, :b].slice }
show { [:a, :b].slice(1, 1, 1) }
show { [:a, :b, :c].slice(1, 2) }
show { [:a, :b, :c].slice(1..) }
show { [:a, :b, :c].slice(-1) }
