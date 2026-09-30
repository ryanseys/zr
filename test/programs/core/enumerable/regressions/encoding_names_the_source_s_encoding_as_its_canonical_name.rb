# SourceEncodingNode — the `__ENCODING__` keyword.
#
# Sources are UTF-8; __ENCODING__ is an Encoding value whose to_s
# returns the canonical name.

puts __ENCODING__.to_s
