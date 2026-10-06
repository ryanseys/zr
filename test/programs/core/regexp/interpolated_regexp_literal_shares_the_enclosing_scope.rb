word = "wor"
r = /#{word}ld/
puts r.match?("world")
puts r.source
