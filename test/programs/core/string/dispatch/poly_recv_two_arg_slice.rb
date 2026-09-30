# 2-arg `recv[start, length]` on a receiver of unknown type. A String
# value gives a substring, and an Array value gives a length-N slice,
# not only element 0.
#
# Also: `puts arr` prints one element per line, as in MRI, not the
# array's inspect form.

def tr(s, length: 30)
  s[0, length]
end

puts tr("Hello world this is a long string")
puts tr([1, 2, 3, 4, 5])
puts tr([10.5, 20.5, 30.5])
puts tr(["a", "b", "c"])
