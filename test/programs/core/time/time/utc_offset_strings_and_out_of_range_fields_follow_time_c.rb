def t
  p yield
rescue ArgumentError => e
  puts e.message
end
t { Time.at(0, in: "+25:00") }
t { Time.at(0, in: "+24:00") }
t { Time.at(0, in: "+23:60") }
t { Time.at(0, in: 86400) }
t { Time.at(0, in: "+0930").utc_offset }
t { Time.at(0, in: "-093015").utc_offset }
t { Time.at(0, in: "utc").utc? }
t { Time.at(0, in: "-00:00").utc? }
t { Time.new(2000, 1, 32) }
t { Time.new(2000, 1, 0) }
t { Time.new(2000, 1, 1, 25) }
t { Time.new(2000, 1, 1, 32) }
t { Time.new(2000, 1, 1, 24, 1) }
t { Time.new(2000, 1, 1, 0, 60) }
t { Time.new(2000, 1, 1, 0, 64) }
t { Time.new(2000, 1, 1, 24, 0, 1) }
t { Time.new(2000, 1, 1, 0, 0, -1) }
