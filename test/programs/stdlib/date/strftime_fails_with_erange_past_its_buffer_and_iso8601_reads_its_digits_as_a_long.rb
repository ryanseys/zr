# date_strftime_alloc doubles its buffer from 1024 bytes until it holds
# 1024 bytes for each byte of the format, so a longer result fails with
# Errno::ERANGE, naming the format. Each NUL-separated piece is a format
# of its own. iso8601, rfc3339, xmlschema and jisx0301 read their digits
# with NUM2LONG, so 3.5 gives 3 and a count below 1 gives none.
require "date"

d = Date.new(2000, 1, 1)
dt = DateTime.new(2000, 1, 1, 4, 5, 6.123456r)
%w[%2147483647c %2147483648c %8191c %8192c %8191Y x%8190Y x%8191Y %16381Yab %16382Yab %1025c %0100000d].each do |format|
  [d, dt].each do |date|
    puts "#{format}: #{date.strftime(format).bytesize}"
  rescue SystemCallError, ArgumentError => e
    puts "#{format}: #{e.class}: #{e.message}"
  end
end
p d.strftime("%5c" * 300).bytesize, d.strftime("%Y\0%5000Y").bytesize, (d.strftime("%Y\0%9000Y") rescue $!)

[3, 3.5, 3.99r, 0, -2, 9, 12].each do |n|
  p [n, dt.iso8601(n), dt.rfc3339(n), dt.xmlschema(n), dt.jisx0301(n)]
end
p((dt.iso8601("3") rescue $!), (dt.iso8601(nil) rescue $!), dt.iso8601, dt.jisx0301)
