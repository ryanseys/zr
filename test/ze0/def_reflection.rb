def twice(n)
  n * 2
end
puts twice(5)
puts respond_to?(:twice, true)
p method(:twice).arity
p method(:twice).parameters
__END__
10
true
1
[[:req, :n]]
