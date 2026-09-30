require "date"
require "time"
t = Time.utc(2024, 1, 2, 3, 4, 5)
d = Date.new(2024, 1, 2)
p t.ctime.encoding, t.iso8601.encoding, d.to_s.encoding, d.inspect.encoding, d.httpdate.encoding
p DateTime.new(2024, 1, 2).to_s.encoding, Date::MONTHNAMES[1].encoding
