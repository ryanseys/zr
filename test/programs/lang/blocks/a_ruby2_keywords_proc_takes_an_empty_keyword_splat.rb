# A ruby2_keywords proc called with an empty `**{}` or `**nil` gets no
# keywords Hash and flags nothing: a positional Hash before it stays an
# ordinary argument.
r2 = proc { |*args| args }
r2.ruby2_keywords
p r2.(1, **{})
p r2.(1, **nil)
p r2.(1, a: 2)
last = r2.(1, { x: 1 }, **{}).last
p [last, Hash.ruby2_keywords_hash?(last)]
p Hash.ruby2_keywords_hash?(r2.(1, a: 2).last)
p r2.(*[], **{})
blk = lambda {}
p r2.(1, a: 2, &blk)
