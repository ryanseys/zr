# Text that is not ASCII-compatible: its Symbol keeps its encoding, and
# the methods that read ASCII digits or names refuse it.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

s = "aaaa".dup.force_encoding("UTF-16BE")
show { s.intern.to_s.encoding }
show { s.intern == :aaaa }
show { s.intern.inspect }
show { "ab".encode("UTF-32LE").to_sym.encoding }
show { "ab".dup.force_encoding("ISO-2022-JP").to_sym.encoding }

show { "77".encode("UTF-16LE").oct }
show { "ff".encode("UTF-16BE").hex }
show { "ff".dup.force_encoding("ISO-2022-JP").hex }
show { "ff".hex }
show { "0o17".oct }

show { Encoding.find("utf-8".dup.force_encoding("UTF-16BE")) }
show { Encoding.find("utf-8") }
