# the non-local return aborts the rest of the method
def compute
  r = proc { return 7 }.call
  r + 100
end
p compute

