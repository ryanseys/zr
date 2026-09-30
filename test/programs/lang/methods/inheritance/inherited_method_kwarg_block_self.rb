# Two checks, from the shape of a Rails controller test:
#
# 1. In `def f(x, y = @ivar)`, the default value of `y` is the object
#    in @ivar. Two sibling classes (Foo and Bar) both define `status`
#    and `body`. `r` must be the Bar in @resp, not the first class that
#    has those methods. The model is
#    `assert_response(expected, response = @__response)`.
#
# 2. A block given to a method runs with the `self` of the code that
#    wrote the block. A call inside the block to a method of that
#    `self` goes to the correct object.

class Foo
  attr_accessor :status, :body
  def initialize
    @status = 100
    @body = "Foo"
  end
end

class Bar
  attr_accessor :status, :body
  def initialize
    @status = 200
    @body = "Bar"
  end
end

class Outer
  def initialize
    @resp = Bar.new
  end

  # `r` is the Bar in @resp, not a Foo, which also defines
  # .status/.body.
  def check(expected, r = @resp)
    raise "got status=#{r.status}, expected=#{expected}" unless r.status == expected
    raise "got body=#{r.body}" unless r.body == "Bar"
  end

  # The block given to `helper` calls `check` on the Outer that
  # wrote the block.
  def helper(label)
    yield
    puts label
  end

  def run
    helper("from-outer") do
      check(200)
    end
  end
end

Outer.new.run
puts "OK"
