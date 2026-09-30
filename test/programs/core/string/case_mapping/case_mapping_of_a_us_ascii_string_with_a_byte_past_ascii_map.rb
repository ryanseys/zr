s = "A\xE9b".force_encoding("US-ASCII")
def t(name)
  r = yield
  p [name, r.b, r.encoding]
rescue => e
  p [name, e.class, e.message]
end
t(:downcase) { s.downcase }
t(:upcase) { s.upcase }
t(:swapcase) { s.swapcase }
t(:capitalize) { s.capitalize }
t(:downcase!) { s.dup.downcase! }
