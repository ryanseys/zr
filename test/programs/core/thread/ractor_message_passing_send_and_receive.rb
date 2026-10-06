worker = Ractor.new do
  msg = Ractor.receive
  msg * 10
end
worker.send(7)
puts worker.value
