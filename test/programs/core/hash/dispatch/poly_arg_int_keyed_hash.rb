# `if status.is_a?(Integer)` inside a method where status can be of
# more than one type (the callers pass different types). The
# then-arm uses status as the key into an Integer-keyed hash, with
# `[]`, has_key? and fetch. The is_a? guard makes sure the key is
# an Integer.

def lookup(status)
  table = { 200 => "OK", 404 => "NotFound" }
  if status.is_a?(Integer)
    return table.fetch(status, "x")
  end
  "no"
end

puts lookup(200)
puts lookup(404)
puts lookup("nope")

def has_status?(status)
  table = { 200 => "OK" }
  if status.is_a?(Integer)
    return table.has_key?(status)
  end
  false
end

puts has_status?(200)
puts has_status?("nope")
