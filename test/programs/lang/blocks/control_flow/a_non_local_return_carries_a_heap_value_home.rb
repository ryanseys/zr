# heap (string) return value
def smethod
  proc { return "early" }.call
  "late"
end
p smethod

