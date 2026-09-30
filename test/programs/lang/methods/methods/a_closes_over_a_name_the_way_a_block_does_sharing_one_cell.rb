def opt(a, b = 10, c = b + 1)
  [a, b, c]
end

def rest(a, *r)
  [a, r]
end

def post(a, *m, z)
  [a, m, z]
end

def kw(a:, b: 5)
  [a, b]
end

def kwrest(a, **o)
  [a, o]
end

def blockp(a, &b)
  b.nil? ? :none : b.call(a)
end

def everything(a, b = 2, *m, z, k:, j: 9, **o, &blk)
  [a, b, m, z, k, j, o, blk.nil?]
end

class Box
  def initialize(value, label: "box")
    @value = value
    @label = label
  end

  def to_s
    "#{@label}=#{@value}"
  end

  def with(*extra, **opts)
    [@value, extra, opts]
  end

  def each_pair
    @value.each { |v| yield(v, @label) }
  end
end

# A `->` closes over a name the same way a block does: one shared cell,
# not a copy taken where the lambda was written.
tally = 0
count = ->(n) { tally += n }
count.call(3)
count.call(4)
p tally

