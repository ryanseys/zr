# Every reader and parser of Date and DateTime checks the string's length
# first, as check_limit does: at most 128 bytes with no keywords, at most
# `limit:` bytes with one, and no limit with `limit: nil` or with other
# keywords only. The _iso8601 family lets nil through to the reader;
# _parse converts it first.
require "date"

long = "2001-02-03T04:05:06+00:00" + " " * 120
calls = {
  "Date._parse" => ->(s, **o) { Date._parse(s, **o) },
  "Date.parse" => ->(s, **o) { Date.parse(s, **o) },
  "Date._iso8601" => ->(s, **o) { Date._iso8601(s, **o) },
  "Date.iso8601" => ->(s, **o) { Date.iso8601(s, **o) },
  "Date._rfc3339" => ->(s, **o) { Date._rfc3339(s, **o) },
  "Date._xmlschema" => ->(s, **o) { Date._xmlschema(s, **o) },
  "Date._rfc2822" => ->(s, **o) { Date._rfc2822(s, **o) },
  "Date._rfc822" => ->(s, **o) { Date._rfc822(s, **o) },
  "Date._httpdate" => ->(s, **o) { Date._httpdate(s, **o) },
  "Date._jisx0301" => ->(s, **o) { Date._jisx0301(s, **o) },
  "DateTime.parse" => ->(s, **o) { DateTime.parse(s, **o) },
  "DateTime.iso8601" => ->(s, **o) { DateTime.iso8601(s, **o) },
  "DateTime.rfc3339" => ->(s, **o) { DateTime.rfc3339(s, **o) },
  "DateTime.xmlschema" => ->(s, **o) { DateTime.xmlschema(s, **o) },
  "DateTime.jisx0301" => ->(s, **o) { DateTime.jisx0301("H13.02.03T04:05:06+00:00" + s[25..], **o) },
}
calls.each do |name, call|
  results = [{}, { limit: 200 }, { limit: nil }, { foo: 1 }, { limit: 10 }, { limit: -1 }, { limit: 3.9 }].map do |opts|
    call.call(long, **opts).class
  rescue ArgumentError, TypeError, Date::Error => e
    "#{e.class}: #{e.message}"
  end
  puts "#{name}: #{results.join(" | ")}"
end
p Date._iso8601(nil), Date._rfc3339(nil, limit: 1), (Date._parse(nil) rescue $!), (Date._parse(:x) rescue $!)
p (Date._iso8601("2001-02-03", limit: "3") rescue $!)
p Date.iso8601("2001-02-03", Date::GREGORIAN, limit: 20).start
p DateTime.iso8601("2001-02-03T04:05:06.123456+00:00", limit: 64).sec_fraction
p Date.parse, DateTime.parse
