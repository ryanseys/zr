# Asking whether a user class owns the CALLED name: a class that defines
# `length` does not change `empty?` on an Array or a String. The receiver
# at run time decides the answer.
class Sized
  def length
    0
  end
end

class Baggy
  def empty?
    true
  end
end

opts = { n: 1, list: [2], s: 'ab', e: [] }
p opts[:list].empty?
p opts[:e].empty?
p opts[:s].empty?
p [2].empty?

# a user class that owns the name wins
things = [Baggy.new, [1]]
p things.first.empty?

# and a user object with no #empty? raises rather than answering true
sized = [Sized.new, 1]
begin
  p sized.first.empty?
rescue NoMethodError => e
  puts "NoMethodError"
end
