# A BEGIN block in a BEGIN block runs before the block that holds it, as
# ruby lists each block when the parser closes it.
BEGIN {
  puts "b1"
}

BEGIN {
  puts "b2"

  BEGIN {
    puts "b2-1"

    BEGIN {
      puts "b2-1-1"
    }
  }

  BEGIN {
    puts "b2-2"
  }
}

puts "main"

BEGIN {
  puts "b3"
}
