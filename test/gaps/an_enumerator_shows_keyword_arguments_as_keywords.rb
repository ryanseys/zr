# An enumerator made by a call with keywords shows them as keywords in
# inspect, as CRuby records the kw_splat flag of the call. zr loses that
# flag, and shows a Hash.
puts (0..10).each_with_object(a: 1).inspect
