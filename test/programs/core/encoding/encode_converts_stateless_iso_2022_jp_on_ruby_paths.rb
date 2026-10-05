# String#encode to and from stateless-ISO-2022-JP takes ruby's own
# transcoder steps: no detour through UTF-8, and errors in its words.
p "\e$B~~\e(B".force_encoding("iso-2022-jp").encode("stateless-ISO-2022-JP").b
s = "\e$B~~\e(B".force_encoding("iso-2022-jp")
p s.encode("stateless-ISO-2022-JP").encode("ISO-2022-JP") == s
p (("\x92\xA1x".force_encoding("stateless-iso-2022-jp").encode("iso-2022-jp", invalid: :replace)) rescue $!)
p (("\x92\xA1x".force_encoding("stateless-iso-2022-jp").encode("utf-8")) rescue $!)
p (("\x92\xA4\xA2".force_encoding("stateless-iso-2022-jp").encode("utf-8")) rescue $!)
p "あ".encode("stateless-ISO-2022-JP").b
