# `Regexp.new(string, integer)`: the integer's FIXEDENCODING and
# NOENCODING bits count, as rb_reg_initialize_str reads them, and the
# encoding comes from the source and its escapes as rb_reg_preprocess
# finds it -- a non-ASCII source fixes it, `\xff` in a UTF-8 source is an
# invalid multibyte escape, `/n` with a non-ASCII character refuses, and
# the source keeps US-ASCII when it is plain ASCII. None of it shows as
# an instance variable.
[0, 16, 32, 33, 48, 64, 7, 23].each do |o|
  ["a", "é", "\\xff"].each do |s|
    r = begin
      Regexp.new(s, o)
    rescue RegexpError => e
      next p [o, s, e]
    end
    p [o, s, r.options, r.encoding, r.fixed_encoding?, r.inspect, r.source.encoding]
  end
end
p Regexp.new(/a/u).options, Regexp.new(/a/n).options, Regexp.new(/a/u).encoding, Regexp.new(/a/n).encoding
p /a/n.instance_variables, /a/u.instance_variables, Regexp.new("a", 16).instance_variables

__END__
[0, "a", 0, #<Encoding:US-ASCII>, false, "/a/", #<Encoding:US-ASCII>]
[0, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
[0, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
[16, "a", 16, #<Encoding:UTF-8>, true, "/a/", #<Encoding:UTF-8>]
[16, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
[16, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
[32, "a", 32, #<Encoding:US-ASCII>, false, "/a/n", #<Encoding:US-ASCII>]
[32, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/>]
[32, "\\xff", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/n", #<Encoding:BINARY (ASCII-8BIT)>]
[33, "a", 33, #<Encoding:US-ASCII>, false, "/a/in", #<Encoding:US-ASCII>]
[33, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/i>]
[33, "\\xff", 49, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/in", #<Encoding:BINARY (ASCII-8BIT)>]
[48, "a", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/a/n", #<Encoding:BINARY (ASCII-8BIT)>]
[48, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/>]
[48, "\\xff", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/n", #<Encoding:BINARY (ASCII-8BIT)>]
[64, "a", 0, #<Encoding:US-ASCII>, false, "/a/", #<Encoding:US-ASCII>]
[64, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
[64, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
[7, "a", 7, #<Encoding:US-ASCII>, false, "/a/mix", #<Encoding:US-ASCII>]
[7, "é", 23, #<Encoding:UTF-8>, true, "/é/mix", #<Encoding:UTF-8>]
[7, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/mix>]
[23, "a", 23, #<Encoding:UTF-8>, true, "/a/mix", #<Encoding:UTF-8>]
[23, "é", 23, #<Encoding:UTF-8>, true, "/é/mix", #<Encoding:UTF-8>]
[23, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/mix>]
16
32
#<Encoding:UTF-8>
#<Encoding:US-ASCII>
[]
[]
[]
