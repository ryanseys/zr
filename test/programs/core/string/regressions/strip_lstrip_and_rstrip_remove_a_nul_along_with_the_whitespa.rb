# String#strip / #lstrip / #rstrip remove the NUL byte along with ASCII
# whitespace, matching CRuby.
p "\0 abc \0".strip
p "abc\0\0".rstrip
p "\0\0abc".lstrip
p "  \t\nx\r\f ".strip
p "\0".strip
p "no change".strip
