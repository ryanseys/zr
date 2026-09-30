# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_sc_classify(sym)
  case sym
  when :red then "warm"
  when :orange then "warm"
  when :blue then "cool"
  when :green then "cool"
  else "unknown"
  end
end

def t_sym_case
  puts t_sc_classify(:red)
  puts t_sc_classify(:orange)
  puts t_sc_classify(:blue)
  puts t_sc_classify(:purple)
end
t_sym_case
