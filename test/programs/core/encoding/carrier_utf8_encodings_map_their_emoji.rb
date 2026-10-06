# UTF8-DoCoMo, UTF8-KDDI and UTF8-SoftBank are UTF-8 whose private-use
# emoji ruby maps to and from Unicode's own, by the tables of
# enc/trans/emoji-exchange-tbl.rb. This runtime carries no such tables
# yet, so a conversion that names one of them stops by name.
["☀", "\u{1F4A9}", "aé日"].each do |text|
  %w[UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].each do |carrier|
    p [carrier, (text.encode(carrier).b rescue $!.message)]
  end
end
p "\u{E63E}".dup.force_encoding("UTF8-DoCoMo").encode("UTF-8")
p "\u{E488}".dup.force_encoding("UTF8-KDDI").encode("UTF-8")
p "\u{E6A0}".dup.force_encoding("UTF8-DoCoMo").encode("UTF-8", undef: :replace)
p "\u{E63E}".dup.force_encoding("UTF8-DoCoMo").encode("UTF8-KDDI").b

