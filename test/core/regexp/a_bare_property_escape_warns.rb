def t(label)
  r = begin
    yield.inspect
  rescue => e
    e.class.to_s
  end
  puts label + " | " + r
end

t("bs-K")   { Regexp.new("a\\Kb") =~ "ab" }
t("bare-p") { Regexp.new("\\p").match("p")[0] }
t("pL")     { Regexp.new("\\pL").match("pL")[0] }
__END__
bs-K | 0
bare-p | "p"
pL | "pL"
#@ stderr
core/regexp/a_bare_property_escape_warns.rb:11: warning: invalid Unicode Property \p: /\p/
core/regexp/a_bare_property_escape_warns.rb:12: warning: invalid Unicode Property \p: /\pL/
