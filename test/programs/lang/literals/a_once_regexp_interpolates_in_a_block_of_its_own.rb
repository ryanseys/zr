# CRuby compiles the interpolation of a `/#{...}/o` regexp as a block of
# its own, which runs once per site. A backtrace or `caller` from inside
# it shows `block in`, and it reads and writes the method's locals.
def make(i) = /#{raise "no" if i == 1; i}/o

begin
  make(1)
rescue => e
  puts e.backtrace.map { |line| line.sub(/\A.*?:/, "") }
end

def label(i) = /#{$label = caller(0, 1).first.sub(/\A.*?:/, ""); i}/o
label(2)
p $label

def writes(i)
  r = /#{w = i * 2}/o
  [r, w]
end
p writes(3)
p writes(4)

def counted
  calls = 0
  3.times.map { /x#{calls += 1}/o }.uniq.then { [_1, calls] }
end
p counted

def nested
  [1, 2].map { |v| /#{v}#{yield}/o }
end
p nested { :y }

r = /a#{%w[b c].join}/o
p r, "zabc" =~ r, $~[0]
