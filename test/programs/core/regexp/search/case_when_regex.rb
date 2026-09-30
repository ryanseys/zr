# `case <string> when /regex/` matches the string against the regex.
case "hello"
when /^h/
  puts "starts with h"
when /world/
  puts "contains world"
end

case "world!"
when /^h/
  puts "starts with h"
when /world/
  puts "contains world"
end

case "abc"
when /xy/
  puts "match"
else
  puts "no match"
end
