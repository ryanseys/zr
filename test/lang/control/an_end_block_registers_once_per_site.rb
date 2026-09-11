# `END { }` registers its block the first time its site runs and never
# again, however often the site is reached; two sites register two.
3.times { END { puts "end in a loop" } }
2.times do |i|
  END { puts "second site" }
end
puts "body"

__END__
body
second site
end in a loop
