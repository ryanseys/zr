# A non-literal ndigits is used, not ignored: 1.234.round(n) with n = 2 is
# 1.23. Positive ndigits gives a Float, as in CRuby. For ndigits <= 0 the
# example calls to_i, so it checks only the value.
n2 = 2
p 1.234.round(n2)        # 1.23 (Float, matches CRuby)
p 3.14159.round(n2)      # 3.14
p 2.71828.ceil(n2)       # 2.72
p 2.71828.floor(n2)      # 2.71
p 9.876.truncate(n2)     # 9.87

nm1 = -1
p 1234.5.round(nm1).to_i # 1230
p 1250.0.floor(nm1).to_i # 1250
p 1241.0.ceil(nm1).to_i  # 1250

n0 = 0
p 1.9.round(n0).to_i     # 2
p 7.8.truncate(n0).to_i  # 7
