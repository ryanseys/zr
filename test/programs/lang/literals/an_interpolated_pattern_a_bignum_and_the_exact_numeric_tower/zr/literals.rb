# frozen_string_literal: true

# The literals whose value only the RUN TIME can build: an interpolated
# pattern or name, an Integer past the inline payload, and the two exact
# numeric towers. `__FILE__` and `__LINE__` are the opposite -- both are
# constants of the compile.

part = "wor"
p(/hello #{part}ld/ =~ "hello world")
p(/#{part}/i.match?("WOR"))
p(/a#{part}c/.source, /a#{part}c/i.options, /a#{part}c/mx.source)

# The pattern is compiled every time, so a bad one raises where it
# stands rather than at the compile.
broken = "["
begin
  /#{broken}/
rescue RegexpError => e
  p e.class
end

p :"sym_#{part}", :"@#{part}", :"x#{1 + 1}y"
p :"#{part}".class, :"#{part}" == :wor

# An Integer past 64 bits is built from its baked digits, and the
# runtime folds it back to the inline form whenever it fits.
big = 123_456_789_012_345_678_901_234_567_890
p big, big + 1, big * big, -big, big.class
p 9_223_372_036_854_775_807, 9_223_372_036_854_775_808
p(-9_223_372_036_854_775_808, -9_223_372_036_854_775_809)
p 18_446_744_073_709_551_616 - 18_446_744_073_709_551_615
p 0xffff_ffff_ffff_ffff_ffff

# Prism pre-rationalizes the decimal form, so both arrive as a pair.
p 1r, 3r, 1.5r, (-2r)
p((3 / 4r), (3 / 4r) + 1r, 1.5r * 2, 1r.class)

p 2i, 1.5i, (-4i), (3i + 4), (2i * 2i), 2i.class

p File.basename(__FILE__), __LINE__
p __ENCODING__

def where = [File.basename(__FILE__), __LINE__]
p where

p defined?(__FILE__), defined?(__LINE__), defined?(__ENCODING__)
p defined?(:"a#{1}"), defined?(/x#{1}/), defined?(1r), defined?(2i)
