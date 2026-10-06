# A block that Enumerable#grep gives to each, called after grep returned,
# sets $~ in the scope that called grep, as CRuby's ifunc keeps its
# svar_lep. The frame that calls the block later keeps its own $~.
Keeper = Class.new do
  include Enumerable

  def each(&b)
    @b = b
  end

  def check1
    check2.merge(check1: $1)
  end

  def check2
    @b.call("foo")
    { check2: $1 }
  end
end

def in_a_method
  obj = Keeper.new
  result = nil
  obj.grep(/(f..)/) { result = $1 }
  p [result, $1]
  p obj.check1
  p [result, $1]
end
in_a_method

def in_a_fiber
  result = nil
  obj = nil
  Fiber.new do
    obj = Keeper.new
    obj.grep(/(f..)/) { result = $1 }
  end.resume
  p [result, $1]
  p obj.check1
  p [result, $1]
end
in_a_fiber

def in_a_thread
  result = nil
  obj = nil
  Thread.new do
    obj = Keeper.new
    obj.grep(/(f..)/) { result = $1 }
  end.join
  p [result, $1]
  p obj.check1
  p [result, $1]
end
in_a_thread

def grep_v_later
  obj = Keeper.new
  seen = []
  obj.grep_v(/(x)/) { |s| seen << [s, $~] }
  obj.check1
  p seen, $~
  $~ = nil
  obj2 = Keeper.new
  obj2.grep_v(/(f)/) { |s| seen << s }
  obj2.check1
  p seen, $1
end
grep_v_later

# The scope that called grep returned before the block runs: its $~ is
# gone, and the caller's own $~ stays as it was.
def made_and_left
  obj = Keeper.new
  obj.grep(/(f..)/) { $1 }
  obj
end
"zzz" =~ /(z)/
kept = made_and_left
p kept.check1, $1

# A grep at the top level, run later.
top = Keeper.new
top.grep(/(o+)/) { $1 }
$~ = nil
p top.check1, $1

# Nested greps, both run at once.
p(%w[ab cd].grep(/(a)|(c)/) { [$1, $2, %w[x y].grep(/(y)/) { $1 }, $1] }, $1)

# A pattern that is not a Regexp, and a match that fails.
p(%w[foo bar].grep("bar") { $~ }, $~)
"m" =~ /m/
p(%w[foo].grep(/zz/) { 1 }, $~)
