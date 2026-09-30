# String#tr_s translates and squeezes adjacent
# identical translated chars (untranslated runs keep their
# duplicates).
puts "hello".tr_s("l", "r")
puts "aaabbbccc".tr_s("a", "x")
# Without squeeze for comparison
puts "hello".tr("l", "r")
puts "aaabbb".tr_s("ab", "xy")
