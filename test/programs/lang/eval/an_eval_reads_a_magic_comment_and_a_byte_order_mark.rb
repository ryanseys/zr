# An eval's code takes its encoding from a magic comment on its first
# line, with or without spaces before the `=`, and a UTF-8 byte order
# mark makes it UTF-8; with neither, it has its String's encoding.
x = nil
eval "\xef\xbb\xbf x = __ENCODING__".b
p x
eval "# coding = utf-8\nx = __ENCODING__".encode("US-ASCII")
p x
eval "# coding: utf-8\nx = __ENCODING__".encode("US-ASCII")
p x
eval "# -*- coding: euc-jp -*-\nx = __ENCODING__"
p x
eval "x = __ENCODING__".encode("US-ASCII")
p x
begin
  eval "\xef".b
rescue NameError => e
  p e.class
end
