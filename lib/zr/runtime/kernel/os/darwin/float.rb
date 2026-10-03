module Zr::Kern
  # darwin's libm returns exact cos and sin values for a multiple of pi.

  # Returns cos(pi * x) and sin(pi * x).
  #: (f64) -> f64
  def zr_os_cospi(x)
    Libc.__cospi(x)
  end

  #: (f64) -> f64
  def zr_os_sinpi(x)
    Libc.__sinpi(x)
  end
end
