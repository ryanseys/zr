# A `begin ... end while` loop in a block, with more code after it. The
# compiler laid the loop's exit out before the loop's body, and joined
# the exit into the body's last block. The join moved code that reads
# the body's values above the body, and the build stopped with "no type
# for vN". Found by zr-dev fuzz.
def unit(name)
  puts "#{name}: #{yield.inspect}"
rescue StandardError => e
  puts "#{name}: #{e.class}: #{e.message}"
end

def show(label, value) = puts("#{label}: #{value.inspect}")

unit("cycle") do
  begin
    [].cycle.first(5).take(2)
  end while nil
  [10, 2, 7, 0, 10**0]
end

unit("first") do
  begin
    [].cycle.first(5)
  end while nil
  show("flatten", [].flatten())
end

unit("show") do
  begin
    show("in", [])
  end while nil
  show("after", [[1, [2]]].flatten())
end

# The loop runs more than once, and its values reach the code after it.
unit("counted") do
  i = 0
  seen = []
  begin
    seen << [i].cycle.first(2).take(1)
    i += 1
  end while i < 3
  [seen, i, 2**i]
end

unit("until") do
  n = 5
  begin
    n -= 2
  end until n < 0
  [n, [n].cycle.first(3)]
end

# The same shapes in a lambda, a method and a proc.
l = lambda do
  begin
    [].cycle.first(5).take(2)
  end while nil
  [1, 2, 3].sum { |x| x**2 }
end
p l.call

def after_loop(k)
  begin
    k = [k].cycle.first(2).sum
  end while k < 10
  [k, k.digits]
end
p after_loop(1)

pr = proc do |a|
  begin
    a = a.to_s * 2
  end while a.size < 4
  [a, a.size]
end
p pr.call("x")
