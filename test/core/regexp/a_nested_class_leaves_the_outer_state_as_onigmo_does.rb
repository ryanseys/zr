# A nested character class leaves the outer class's state as Onigmo
# leaves it: a value before it still pends, and a '-' after a leading
# one is a plain character with no warning.

$VERBOSE = true
pats = ["[[[:alnum:]]-_.]", "[a[x]-c]", "[[x]a-c]", "[a-b[x]-z]", "[[a]-[b]]", "[[:alpha:][0-9]-]", "[x[y]]", "[[a-c]&&[b]]"]
pats.each do |s|
  begin
    r = Regexp.new(s)
    p [s, %w[a b _ - . x y z 5].select { |c| r.match?(c) }]
  rescue RegexpError => e
    p [s, e.message]
  end
end

__END__
["[[[:alnum:]]-_.]", ["a", "b", "_", "-", ".", "x", "y", "z", "5"]]
["[a[x]-c]", ["a", "b", "x"]]
["[[x]a-c]", ["a", "b", "x"]]
["[a-b[x]-z]", ["a", "b", "-", "x", "z"]]
["[[a]-[b]]", ["a", "b", "-"]]
["[[:alpha:][0-9]-]", ["a", "b", "-", "x", "y", "z", "5"]]
["[x[y]]", ["x", "y"]]
["[[a-c]&&[b]]", ["b"]]
#@ stderr
core/regexp/a_nested_class_leaves_the_outer_state_as_onigmo_does.rb:9: warning: character class has '-' without escape: /[a-b[x]-z]/
