# A class may define method_missing and call it explicitly like any other
# method.
class Proxy
  def initialize(label)
    @label = label
  end

  def method_missing(name, *args)
    "#{@label}:#{name}/#{args.length}"
  end
end

p = Proxy.new("px")
puts p.method_missing(:foo)
puts p.method_missing(:bar, 1, 2)
