# Regexp#source returns the original pattern string;
# #options returns the CRuby flag bitmask (1=IGNORECASE, 2=EXTENDED,
# 4=MULTILINE).
# Another example covers named_captures.
puts /hello/.source
puts /hello/i.options
puts /hello/.options
puts /world/m.options
puts /pat/x.options
