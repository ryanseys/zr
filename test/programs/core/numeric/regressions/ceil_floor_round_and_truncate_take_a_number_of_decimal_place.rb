puts 3.14159.round(2)
puts 3.14159.round(4)
puts 1.5.round(1)
puts 2.5.round(1)
puts 3.14159.ceil(2)
puts 3.14159.ceil(4)
puts 1.001.ceil(2)
puts 3.14159.floor(2)
puts 3.14159.floor(4)
puts 1.999.floor(2)
puts 3.14159.truncate(2)
puts 3.14159.truncate(4)
puts (-1.567).truncate(2)
puts 3.14.round
puts 3.14.ceil
puts 3.14.floor
puts 3.14.truncate
# Negative precision: the example compares with ==, so it checks
# only the value, not whether the result is an Integer or a Float.
puts 12345.6789.floor(-2) == 12300
puts 12345.6789.ceil(-2) == 12400
puts 12345.6789.round(-1) == 12350
puts 12345.6789.truncate(-2) == 12300
puts (-12345.6789).floor(-2) == -12400
puts (-12345.6789).ceil(-2) == -12300
