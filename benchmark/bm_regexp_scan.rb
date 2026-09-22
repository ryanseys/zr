# Regexp over a log-like text: scan, gsub with captures, split, match?
# and a case-insensitive search, the engine's common paths.
line = "2026-09-16 12:34:56 INFO  user=alice id=4821 path=/api/v1/items?q=café took=12.5ms\n"
text = line * 2000
count = 0
bytes = 0
10.times do
  count += text.scan(/id=(\d+)/).size
  bytes += text.gsub(/(\w+)=(\S+)/) { "#{$2}:#{$1}" }.bytesize
  count += text.split(/\s+/).size
  count += text.each_line.count { |l| l.match?(/\bpath=\/api\/v\d+\/\w+/) }
  count += text.scan(/INFO|WARN|ERROR/i).size
  count += text.scan(/caf./).size
end
puts count, bytes
