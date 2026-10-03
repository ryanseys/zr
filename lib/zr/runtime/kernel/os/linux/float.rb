module Zr::Kern
  # musl's libm has no cospi or sinpi, so ruby multiplies by pi first.
  #: (f64) -> f64
  def zr_os_cospi(x)
    zr_cos_of_pi_times(x)
  end

  #: (f64) -> f64
  def zr_os_sinpi(x)
    zr_sin_of_pi_times(x)
  end
end
