def t(s, to, **o)
  r = s.encode(to, **o)
  p [r, r.encoding]
rescue => e
  p [e.class, e.message]
end
t "a\xE9".force_encoding("US-ASCII"), "UTF-8", invalid: :replace
t "a\xE9b", "UTF-8", invalid: :replace
t "a\xE9b", "UTF-8", invalid: :replace, replace: "?"
t "a\xE9b", "UTF-16LE", invalid: :replace
t "a\xE9b".force_encoding("US-ASCII"), "ISO-8859-1", invalid: :replace
