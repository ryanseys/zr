# A method parameter is always generically typed, so `freeze`/`frozen?`
# take the universal path, not one of the type-gated fast paths.

class Once
  def run(x)
    x.freeze
    puts x.frozen?
  end
end
Once.new.run([1])
Once.new.run(42)
