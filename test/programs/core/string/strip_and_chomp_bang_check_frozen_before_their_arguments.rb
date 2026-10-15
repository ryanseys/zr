# strip!, lstrip!, rstrip! and chomp! check a frozen receiver before they
# read their arguments, so a frozen String raises FrozenError even with a
# bad argument or nothing to remove. A chilled literal warns once.
def t(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

t("strip! bad") { "".freeze.strip!(-1) }
t("lstrip! bad") { "ab".freeze.lstrip!(:x) }
t("rstrip! bad") { "ab".freeze.rstrip!(nil) }
t("chomp! empty bad") { "".freeze.chomp!(1) }
t("chomp! bad") { "a".freeze.chomp!(1) }
t("strip! nothing") { "ab".freeze.strip! }
t("strip! thawed bad") { (+"ab").strip!(1) }
t("strip! selector") { (+"xxabx").strip!("x") }
t("chomp! empty") { (+"").chomp!(1) }

Warning[:deprecated] = true
t("chilled") { "  ab  ".strip! }
