def base
  40
end
f = ->(x) { base + x }
puts f.call(2)
