# ruby gives a Hash literal of three to eight pairs a slot that holds
# them all, so ObjectSpace.dump calls it an ar_table. zr's Hash cells do
# not follow ruby's slot sizes, and a Hash past two pairs dumps as an
# st_table here.
require "objspace"
def d(h) = ObjectSpace.dump(h).include?('"ar_table":true') ? :ar : :st
p [d({a: 1, b: 2, c: 3}), d({a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8})]
