# frozen_string_literal: true

# `BEGIN { }` runs before the rest of the file, in the order the file
# writes them. `END { }` runs at exit, last registered first, which is
# the queue `at_exit` shares.

puts "main"
BEGIN { puts "begin one" }
END { puts "end one" }
BEGIN { puts "begin two" }
END { puts "end two" }
at_exit { puts "at_exit" }
puts "done"

# A `BEGIN` shares the top-level names, so what it writes is there after.
BEGIN { started = :yes }
p defined?(started)

# An `END` reads the enclosing names by reference, so it sees the value
# they hold at exit, not the one they held where it was written.
counter = 1
END { puts "end saw counter=#{counter}" }
counter = 2
__END__
begin one
begin two
main
done
"local-variable"
end saw counter=2
at_exit
end two
end one
