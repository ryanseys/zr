r = Ractor.new do
  a = Ractor.receive
  b = Ractor.receive
  c = Ractor.receive
  a * 100 + b * 10 + c
end
r.send(1)
r.send(2)
r.send(3)
puts r.value
