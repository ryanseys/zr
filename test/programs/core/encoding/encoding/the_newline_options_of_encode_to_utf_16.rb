def t(s, to, **o)
  r = s.encode(to, **o)
  p [r.b, r.encoding]
rescue => e
  p [e.class, e.message]
end
t "a\nb", "UTF-16LE", crlf_newline: true
t "a\r\nb", "UTF-16BE", universal_newline: true
t "a\nb", "UTF-32LE", cr_newline: true
t "a\r\nb".encode("UTF-16LE"), "UTF-8", universal_newline: true
