# Psych resolves plain scalars by YAML 1.1 rules: yes/no/on/off (any
# case) are booleans, Null/NULL are nil, 017 is OCTAL 15, 1:02:03 is the
# sexagesimal 3723, and "1.0e3"/"1E2" stay STRINGS (the 1.1 float form
# needs a digit after the point). A resolver that applies 1.2 rules to all
# of these has the Norway problem in both directions.
# (Found by the 2026-08-24 probe sweep.)
require "yaml"
p YAML.safe_load("[y, Y, yes, Yes, YES, n, no, No, NO, on, On, off, true, false]")
p YAML.safe_load("[~, null, Null, NULL, '']")
p YAML.safe_load("[017, 0x1A, 1_000, +5]")
p YAML.safe_load("t: 1:02:03")
p YAML.safe_load("[1.0e3, .5, 5., 1E2]")
p YAML.safe_load("no: 1\nyes: 2").keys
