# Array#join takes a separator whose type is only known at run time (an
# ivar/reader that holds values of more than one type across the program).
# The separator joins as its String value.
class P
  def initialize(app, sep)
    @app = app
    @sep = sep
  end
  def app
    @app || "fallback"
  end
  def sep
    @sep
  end
  def render
    [app, "Dash"].compact.join(sep)
  end
end

puts P.new("MyApp", " : ").render
P.new("X", 5)   # a second call site with a non-string separator widens @sep to poly
