# darwin's libm answers cos and sin of a multiple of pi exactly.
Machine.import "__cospi", [F64] => F64
Machine.import "__sinpi", [F64] => F64

# cos(pi * x) and sin(pi * x).
sig [F64] => F64
machine def zr_os_cospi(x)
  __cospi(x)
end

sig [F64] => F64
machine def zr_os_sinpi(x)
  __sinpi(x)
end
