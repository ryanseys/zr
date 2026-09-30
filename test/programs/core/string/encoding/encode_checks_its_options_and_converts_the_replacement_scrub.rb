def t
  p yield
rescue ArgumentError, EncodingError => e
  puts "#{e.class}: #{e.message}"
end
t { "é".encode("US-ASCII", undef: :replace, replace: "é") }
t { "é".encode("ISO-8859-1", undef: :replace, replace: "あ") }
t { "a".encode("US-ASCII", undef: :replace, replace: "é") }
t { "é".encode("US-ASCII", undef: :replace, replace: "\xff".b) }
t { "a".encode("UTF-8", undef: :replace, replace: "\xff") }
t { "a".encode("UTF-8", invalid: :bogus) }
t { "a".encode("UTF-8", undef: "replace") }
t { "a\xffb".force_encoding("US-ASCII").scrub("é") }
t { "a\xffb".scrub("\xff") }
t { "a\xffb".scrub { "é".encode("UTF-16LE") } }
t { "a\xffb".scrub("?") }
