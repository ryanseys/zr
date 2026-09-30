# An uncalled `def f(x); @typed = x; end`, where no caller gives the
# param a value and the ivar holds a String. The program still runs.

class T_uncalled_method_dce_C
  def initialize
    @body = ""
  end

  # Never called. @body holds a String.
  def render(html)
    @body = html
  end
end

c = T_uncalled_method_dce_C.new
puts "ok"
