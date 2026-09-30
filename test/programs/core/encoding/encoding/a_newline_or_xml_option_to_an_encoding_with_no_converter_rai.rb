def t(to, **o)
  r = "a<b".encode(to, **o)
  p [to, r.b]
rescue => e
  p [to, e.class, e.message]
end
t "EUC-TW", xml: :text
t "Emacs-Mule", crlf_newline: true
t "GB1988", xml: :attr
t "macThai", xml: :text
t "EUC-TW"
