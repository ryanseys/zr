# String#tr / tr_s with empty replacement string
# When the to-string is empty, matched characters are deleted.

puts "abc".tr("a", "").inspect
puts "abcdef".tr("a-c", "").inspect
puts "aabbbccc".tr_s("ab", "").inspect
