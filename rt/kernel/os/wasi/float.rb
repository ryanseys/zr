# WASI's libm has no cospi or sinpi, so ruby multiplies by pi first, as
# complex.c does where the pair is missing.
Machine.import "cos", [F64] => F64
Machine.import "sin", [F64] => F64

# pi, by its bits.
PI_BITS = 4614256656552045848

sig [F64] => F64
machine def zr_os_cospi(x)
  cos(x * Machine.f64(PI_BITS))
end

sig [F64] => F64
machine def zr_os_sinpi(x)
  sin(x * Machine.f64(PI_BITS))
end
