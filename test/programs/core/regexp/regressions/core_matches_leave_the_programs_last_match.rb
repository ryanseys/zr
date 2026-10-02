# The core library's own matches leave the program's $~ alone, as ruby's
# C functions do; the methods that ruby defines to set $~ still set it.
# $~ is the frame's own, so each line hands it to `show`.
def show(label, match) = p([label, match && match[0]])

"%w" =~ /%/
begin
  Regexp.new("(")
rescue RegexpError
  nil
end
show :regexp_new, $~
"ab" =~ /b/
format("%a", 1.5)
show :format_a, $~
"cd" =~ /d/
Time.at(0, 5, :nsec).utc.inspect
show :time_inspect, $~
"ef" =~ /f/
"1e3".to_c
show :to_c, $~
"gh" =~ /h/
'"A"'.undump
show :undump, $~
"ij" =~ /j/
"a\r\nb".encode(universal_newline: true)
show :universal_newline, $~
"kl" =~ /l/
require "date"
Date.parse("2024-01-02")
show :date_parse, $~
"mn" =~ /n/
Complex("1+2i")
show :complex_parse, $~

"x".sub("x", "y")
show :sub_sets, $~
"qr".gsub(/r/) { $~[0] }
show :gsub_sets, $~
"st".match?(/t/)
show :match_p_leaves, $~
"uv".scan(/v/)
show :scan_sets, $~
"wx".start_with?(/w/)
show :start_with_sets, $~
"yz".index(/z/)
show :index_sets, $~
