# A `&block` parameter can be called with `blk.call`.

class Foo
  def bar(&blk)
    blk.call(5)
  end
end
puts Foo.new.bar { |x| x * 2 }
