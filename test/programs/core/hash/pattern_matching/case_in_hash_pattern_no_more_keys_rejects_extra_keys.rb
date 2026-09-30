case { a: 1 }
in { a: 1, **nil }
  puts "exact match"
end
case { a: 1, b: 2 }
in { a: 1, **nil }
  puts "should not print"
else
  puts "extra keys rejected"
end
