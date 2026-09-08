puts 6 / 3
puts 6 / 0
__END__
2
#@ stderr
ze0/division_by_zero.rb:2:in 'Integer#/': divided by 0 (ZeroDivisionError)
	from ze0/division_by_zero.rb:2:in '<main>'
#@ exit 1
