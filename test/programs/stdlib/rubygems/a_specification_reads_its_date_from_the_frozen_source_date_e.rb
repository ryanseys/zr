require "rubygems"
e = Gem.source_date_epoch
p e.frozen?, e.utc.equal?(e)
s = Gem::Specification.new { |x| x.name = "a"; x.version = "1" }
p s.date, s.date.utc?
