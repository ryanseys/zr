# WASI's libm has no cospi or sinpi, so ruby multiplies by pi first.
sig [F64] => F64
machine def zr_os_cospi(x)
  zr_cos_of_pi_times(x)
end

sig [F64] => F64
machine def zr_os_sinpi(x)
  zr_sin_of_pi_times(x)
end
