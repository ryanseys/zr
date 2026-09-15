# `"lit".freeze` at any site answers the one frozen String the fstring
# table holds for those bytes, as -"lit" and String#dedup do: the core
# rows ruby defines on String itself leave the literal fast path alone.
p "lit".freeze.equal?("lit".freeze), (-"lit").equal?(-"lit"), (-"lit").equal?("lit".freeze), "x".dedup.equal?("x".freeze)
p nil === nil, [1].freeze.frozen?, "a".freeze.frozen?

__END__
true
true
true
true
true
true
true
