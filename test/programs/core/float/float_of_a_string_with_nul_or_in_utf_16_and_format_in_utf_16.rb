def t
  p yield
rescue ArgumentError, EncodingError => e
  puts "#{e.class}: #{e.message}"
end
t { Float("1.5\0") }
t { Float("1.5\0", exception: false) }
t { Float("1.5".encode("UTF-16LE")) }
t { format("%s".encode("UTF-16LE"), "x") }
