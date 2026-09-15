# native only: the regexps below have no engine in a wasm32 module
# Unicode case mapping: the full tables, the options ruby takes, and
# the grapheme clusters the regex engine finds.
p "abc".upcase, "ABC".downcase, "abc".capitalize, "aBc".swapcase
p "ǳ".capitalize, "ǳ".upcase, "ǳ".downcase, "Ǳ".swapcase
p "ß".upcase, "ﬁ".upcase, "İ".downcase, "ﬄ".upcase
p "ǳǳ".capitalize, "STRASSE".capitalize, "ΣΣ".downcase, "ΑΣ".downcase
p "ΓΕΙΆ".downcase, "γειά".upcase, "ЖУК".downcase, "жук".upcase
p "ÅÄÖ".downcase, "åäö".upcase, "ÅÄÖ".swapcase, "çğışü".upcase
p "İ".downcase(:turkic), "I".downcase(:turkic), "i".upcase(:turkic), "i".capitalize(:turkic)
p "istanbul".upcase(:turkic), "ISTANBUL".downcase(:turkic)
p "ÀBC".upcase(:ascii), "àbc".upcase(:ascii), "ÀBC".downcase(:ascii)
p "ÀBC".downcase(:fold), "ß".downcase(:fold), "ẞ".downcase(:fold), "İ".downcase(:fold)
p "Ì".downcase(:lithuanian), "x".upcase(:turkic, :lithuanian), "x".upcase(:lithuanian, :turkic)
[[:nope], [:fold], [:turkic, :ascii], [:ascii, :turkic], [:turkic, :turkic], [:a, :b, :c]].each do |options|
  "x".upcase(*options)
rescue ArgumentError => e
  puts "#{options.inspect}: #{e.message}"
end
s = +"aBc"
p s.swapcase!, s, s.swapcase!
t = +"ǳ"
p t.capitalize!, t, t.capitalize!
p :abc.upcase, :ABC.downcase, :abc.capitalize, :aBc.swapcase

p "abc".grapheme_clusters, "áb".grapheme_clusters
p "🇦🇧🇨".grapheme_clusters, "👨‍👩‍👦".grapheme_clusters, "a\r\nb".grapheme_clusters
p "áb".each_grapheme_cluster.to_a, "áb".each_grapheme_cluster.size
out = []
p "áb".each_grapheme_cluster { |g| out << g }.equal?("áb".dup) == false, out
