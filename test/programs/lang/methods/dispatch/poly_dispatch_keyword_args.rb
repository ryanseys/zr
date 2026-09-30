# Keyword arguments through a call on a receiver of more than one class
# bind by name, not position. The trailing keyword hash does not go into
# the *rest.
class Config
  attr_reader :log
  def initialize = @log = []
  def str(*opts, default: nil, required: false) = log << [:str, opts, default, required]
  def num(x, scale: 2) = log << [:num, x, scale]
  def any(**kw) = log << [:any, kw]
  def mix(a, *rest, flag: false, **extra) = log << [:mix, a, rest, flag, extra]
end

def run(&) = Config.new.tap { |c| yield c }.log

p run { _1.str "--a", "--b", default: "x", required: true }
p run { _1.str "--c" }
p run { _1.num 7 }
p run { _1.num 7, scale: 5 }
p run { _1.any a: 1, b: "two" }
p run { _1.mix 1, 2, 3, flag: true, other: "x" }
