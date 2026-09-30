# A receiver whose class defines `join`: the call runs the user method, not
# #to_s. An Array reaching the same call still joins.
class Row
  def initialize = @ran = false
  attr_reader :ran

  def join(sep)
    @ran = true
    "row" + sep
  end
end

def joined(v) = v.join("-")

r = Row.new
p joined(r)
p r.ran
p joined(["x", "y"])
p joined([1, 2])

# the zero-argument form reaches the other dispatch, whose array arms had to be
# added alongside the user ones
class Glue
  def join = "glue"
end

def j0(v) = v.join

p j0(Glue.new)
p j0(["a", "b"])
p j0([1, 2])
