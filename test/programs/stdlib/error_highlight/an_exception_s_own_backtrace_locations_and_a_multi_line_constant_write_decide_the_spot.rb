# ErrorHighlight.spot reads the exception's own backtrace_locations, so a
# singleton that gives none leaves no snippet; a constant write whose
# path spans lines has no spot of its own name, as the Spotter finds none.
require "error_highlight"
class Probe
  module OP_CDECL_TEST
    Nil = nil
  end

  def check
    err = begin
      yield
    rescue NameError => e
      e
    end
    spot = ErrorHighlight.spot(err)
    p spot&.slice(:first_lineno, :first_column, :last_lineno, :last_column)
    puts err.detailed_message(highlight: false), "--"
  end

  def run
    check do
      nil.foo + 1
    rescue NoMethodError => exc
      def exc.backtrace_locations = []
      raise
    end
    check do
      OP_CDECL_TEST::
        NotDefined += 1
    end
  end
end
Probe.new.run
e = (nil.bar rescue $!)
class << e
  def backtrace_locations = []
end
p ErrorHighlight.spot(e)
f = (nil.bar rescue $!)
f.singleton_class.prepend(Module.new { def backtrace_locations = [] })
p ErrorHighlight.spot(f)
g = RuntimeError.new("x")
def g.backtrace_locations = []
p ErrorHighlight.spot(g)
