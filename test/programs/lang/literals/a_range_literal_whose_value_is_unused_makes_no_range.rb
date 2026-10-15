# A range literal whose value is not used makes no Range, as ruby's
# compiler drops it: its ends still run, but no check of them raises.
# Used anywhere (an assignment, an argument, a block's value) it does.
def log(x) = (print "<#{x.inspect}>"; x)

a = []
b = Object
a..b
log(1)..log("z")
(:a..1)
(log(2)...log(:q); nil)
puts
p :done

def m(x, y) = (x..y; :m)
p m([], 1)
p [1, 2].map { |v| (v..Object); v }

[-> { r = (a..b) }, -> { p(a..b) }, -> { [1].map { a..b } }, -> { (a..b if true) }].each do |code|
  code.call
rescue ArgumentError => e
  p e.message
end
