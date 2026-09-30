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

