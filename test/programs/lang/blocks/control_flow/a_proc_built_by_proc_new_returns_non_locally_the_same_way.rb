# Proc.new form
def pnew
  Proc.new { return 99 }.call
  -1
end
p pnew

