# The receiver isn't a literal constant, so the call must dispatch
# dynamically to the right class method at run time.

class H1
  def self.run(x); "h1:#{x}"; end
end
class H2
  def self.run(x); "h2:#{x}"; end
end
[H1, H2].each { |h| puts h.run(5) }
handler = H1
puts handler.run(9)
handler = H2
puts handler.run(9)
