# `alias_method :raise!, :raise` / `alias __raise__ raise` (ostruct's and
# delegate's shapes): the source is Kernel's BUILTIN raise, and no user
# method has that name. The alias acts as raise in each call shape,
# including the bare re-raise and the 3-arg form with a custom backtrace.
# CRuby gives the same outputs.

class Reporter
  alias_method :raise!, :raise
  def two_arg
    raise! ArgumentError, "boom"
  rescue ArgumentError => e
    puts e.message
  end
  def re_raise
    begin
      raise IOError, "orig"
    rescue
      raise!
    end
  rescue IOError => e
    puts e.message
  end
  def three_arg
    raise! ArgumentError, "with-bt", caller(0)
  rescue ArgumentError => e
    puts e.message
  end
end
class Failer
  alias __raise__ raise
  def go
    __raise__ NotImplementedError, "need to define"
  rescue NotImplementedError => e
    puts e.message
  end
end
r = Reporter.new
r.two_arg
r.re_raise
r.three_arg
Failer.new.go
