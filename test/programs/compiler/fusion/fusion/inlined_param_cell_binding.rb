# A parameter of an inlined yielding method that an inner block CAPTURES. The
# block and the method body read and write the same variable.
#
# Two receivers so the call cannot fold to one target: the block that assigns
# the captured parameter is inlined once per candidate.
class Conn
  def run(x)
    yield x
  end
end

class Other
  def run(x)
    yield x + 1
  end
end

class Fetch
  def request(url, obj)
    obj.run(url) do |r|
      url = url + r
    end
    yield url
  end
end

p Fetch.new.request(1, Conn.new) { |v| v }
p Fetch.new.request(1, Other.new) { |v| v }

# The same shape where the captured parameter is a String rather than an int,
# so the cell carries a pointer.
class Joiner
  def run(s)
    yield s
  end
end

class Build
  def make(head, obj)
    obj.run("-") do |sep|
      head = head + sep
    end
    head
  end
end
p Build.new.make("a", Joiner.new)

# A parameter captured by a proc that outlives the call: the cell has to be the
# storage both sides see.
class Keep
  def run(n)
    yield n
  end
end

class Hold
  def grab(seed, obj)
    box = nil
    obj.run(seed) do |k|
      seed = seed + k
      box = proc { seed }
    end
    [seed, box.call]
  end
end
p Hold.new.grab(2, Keep.new)
