# darwin's libm returns exact cos and sin values for a multiple of pi.
Machine.import "__cospi", [F64] => F64
Machine.import "__sinpi", [F64] => F64

# Returns cos(pi * x) and sin(pi * x).
sig [F64] => F64
machine def zr_os_cospi(x)
  __cospi(x)
end

sig [F64] => F64
machine def zr_os_sinpi(x)
  __sinpi(x)
end
