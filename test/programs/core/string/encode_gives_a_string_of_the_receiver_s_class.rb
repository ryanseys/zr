# encoded_dup: what encode gives has the receiver's class, which the C
# sets on it with no initialize, converted or not.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

class Mine < String
  def initialize(*) = raise("no initialize")
end
s = Mine.allocate.replace("Rubyע")
t("encode") { [s.encode, s.encode("UTF-8"), s.encode("ISO-8859-8"), s.encode("UTF-16LE", "UTF-8")].map(&:class) }
t("text") { [s.encode("ISO-8859-8").bytes.last, s.encode(xml: :attr)] }
t("frozen") { s.encode.frozen? }
t("encode!") { x = Mine.allocate.replace("a\nb"); x.encode!(crlf_newline: true); [x.class, x] }
t("plain") { "a".encode("UTF-16LE").class }
