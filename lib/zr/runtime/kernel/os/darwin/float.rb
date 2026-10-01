module Zr::Kern
  # darwin's libm returns exact cos and sin values for a multiple of pi.
  Libc.import :__cospi, [F64] => F64
  Libc.import :__sinpi, [F64] => F64

  # Returns cos(pi * x) and sin(pi * x).
  sig [F64] => F64
  def zr_os_cospi(x)
    Libc.__cospi(x)
  end

  sig [F64] => F64
  def zr_os_sinpi(x)
    Libc.__sinpi(x)
  end
end
