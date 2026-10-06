# The gsub block captures `count` like every other escaping block does.

count = 0
"one two three".gsub(/\w+/) { |w| count += 1; w }
puts count
