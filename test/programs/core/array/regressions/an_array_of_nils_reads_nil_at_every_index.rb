# `[nil, nil, ...].first` and `.last` give nil, not 0.
# So `.nil?` is true.
p [nil].first.nil?               # true
p [nil].last.nil?                # true
p [nil, nil, nil].first.nil?     # true
p [nil, nil, nil].last.nil?      # true
