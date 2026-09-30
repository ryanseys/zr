# The loop runs inline, and a `return` from its block runs the ensure
# clauses outside the loop. They read the method's locals.
def first_stop(stop)
  res = +"r"
  begin
    3.times do |i|
      return "early #{i}" if i == stop
      res << i.to_s
    end
    res
  ensure
    puts "ensure #{res}"
  end
end
p first_stop(1)
p first_stop(9)

def nested
  acc = []
  begin
    [1, 2].each do |a|
      begin
        [10, 20].each do |b|
          return acc if a == 2 && b == 20
          acc << a + b
        end
      ensure
        acc << :inner
      end
    end
  ensure
    acc << :outer
  end
end
p nested
