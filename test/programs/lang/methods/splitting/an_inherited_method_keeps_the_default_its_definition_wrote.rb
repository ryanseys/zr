# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Instance method default + inherited dispatch ----
# Same Greeter covers both: direct call and a subclass inheriting
# the defaulted method without redefining it.
class Greeter
  def hello(name = "world")
    puts "Hello, #{name}"
  end
end
class GreeterChild < Greeter
end
Greeter.new.hello                # Hello, world
Greeter.new.hello("Ruby")        # Hello, Ruby
GreeterChild.new.hello           # Hello, world
GreeterChild.new.hello("Ruby")   # Hello, Ruby

