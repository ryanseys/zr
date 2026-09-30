# `Module#===` is real Ruby's instance-of check, so `when Integer` works.

class Widget
end

[5, "s", Widget.new, nil].each do |v|
  case v
  when Integer then puts "int"
  when String then puts "str"
  when Widget then puts "widget"
  else puts "other"
  end
end
