class Animal
  def speak
    "generic"
  end
end

class MyError < StandardError
end

class Risky
  def check(n)
    raise MyError, "bad value: #{n}" if n < 0
    n * 2
  end
end

r = Risky.new
puts r.check(5)
