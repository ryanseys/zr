t = Time.at(1_700_000_000.5).utc
puts t.asctime
p t.to_a
p Time.at(100).to_r
p Time.at(1_700_000_000.7654321).round(3).subsec
puts t.xmlschema(3)
p t.deconstruct_keys([:year, :month])
