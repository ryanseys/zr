# did_you_mean is loaded before the program, as ruby's gem prelude loads
# it, and a NameError names the locals and methods it may have meant.
p require("did_you_mean")
p defined?(DidYouMean)
p DidYouMean::SpellChecker.new(dictionary: %w[length size]).correct("lenght")
first_name = "x"
begin
  frist_name
rescue NameError => e
  puts e.detailed_message(highlight: false)
end

__END__
false
"constant"
["length"]
undefined local variable or method 'frist_name' for main (NameError)

  frist_name
  ^^^^^^^^^^
Did you mean?  first_name
