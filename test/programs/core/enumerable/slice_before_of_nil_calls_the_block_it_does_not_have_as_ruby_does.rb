def t(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

t("array") { [1, nil, 2].slice_before(nil).to_a }
t("enumerator") { [1, nil, 2].each.slice_before(nil).first }
t("empty") { [].slice_before(nil).to_a }
t("size") { [1].slice_before(nil).size }
t("hash") { { a: 1 }.slice_before(nil).to_a }
t("range") { (1..3).slice_before(nil).map(&:size) }
t("false pattern") { [1, false, 2].slice_before(false).to_a }
t("no pattern") { [1].slice_before }
t("after nil") { [1, nil, 2].slice_after(nil).to_a }
t("block") { [1, 2, 3].slice_before(&:even?).to_a }
[1, 2].slice_before(nil).each { p _1 }
