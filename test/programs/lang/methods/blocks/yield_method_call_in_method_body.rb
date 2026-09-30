# A call to a yield-using method on implicit self, from inside
# another instance method's body, passes its literal block. The
# same call works from the top level too.

class C
  def run(name)
    yield
    name
  end

  def call_it
    run("foo") do
      puts "block ran"
    end
  end

  # Variant: default arg in target. Same root cause; just a different
  # arity surface — exercised explicitly because the issue called it
  # out as a separate failure mode.
  def run_with_default(name, count = 1)
    yield
    count
  end

  def call_it_default
    run_with_default("bar", -1) do
      puts "default-arg block ran"
    end
  end
end

# Parent class with the yield method, child calls it via implicit
# self — exercises the new ancestor walk.
class P
  def each_thing
    yield 1
    yield 2
  end
end

class K < P
  def use
    each_thing do |v|
      puts v
    end
  end
end

C.new.call_it
C.new.call_it_default
K.new.use
