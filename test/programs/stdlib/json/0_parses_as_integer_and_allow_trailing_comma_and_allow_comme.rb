# Three parser rows: `-0` parses as INTEGER 0, `allow_trailing_comma: true`
# admits `[1,]`, and `allow_comments: true` admits a trailing `// c`,
# which json 3.0 refuses by default.
# (Found by the 2026-08-24 probe sweep.)
require "json"
def show
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end
show { JSON.parse("[-0]").first }
show { JSON.parse("[1,]", allow_trailing_comma: true) }
show { JSON.parse("[1] // c") }
show { JSON.parse("[1] // c", allow_comments: true) }
