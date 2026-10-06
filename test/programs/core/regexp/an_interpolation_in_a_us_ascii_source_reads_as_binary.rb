# coding: US-ASCII
# In a US-ASCII source a regexp literal reads as binary, so an escape
# past ASCII in what `/#{x}/` interpolates fixes the pattern to binary.
# A String literal in the braces is text of the pattern and keeps the
# source's encoding. Escapes in a String of another encoding read in
# that encoding.
def show(label)
  r = yield
  puts "#{label}: #{r.encoding} #{r.fixed_encoding?}"
rescue => e
  puts "#{label}: #{e.class} #{e.message}"
end
x80 = %q{\x80}.dup.force_encoding("US-ASCII")
xc2 = %q{\xc2\xa1}.dup.force_encoding("US-ASCII")
a = "a".dup.force_encoding("US-ASCII")
show("x80") { /#{x80}/ }
show("xc2") { /#{xc2}/ }
show("a") { /#{a}/ }
show("a x80") { /a#{x80}/ }
show("x80 twice") { /#{x80}#{x80}/ }
show("literal x80") { /#{%q"\x80"}/ }
show("utf8 x80") { /#{%q{\x80}.dup.force_encoding("UTF-8")}/ }
show("utf8 xc2") { /#{%q{\xc2\xa1}.dup.force_encoding("UTF-8")}/ }
show("binary xc2") { /#{%q{\xc2\xa1}.b}/ }
show("xc2 n") { /#{xc2}/n }
show("xc2 o") { /#{xc2}/o }
p(/#{xc2}/ =~ "\xc2\xa1".b)
