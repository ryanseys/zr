module Zr::Kern
  # RUBY_PLATFORM: this architecture, then the C library's part.
  #: () -> value
  def zr_os_ruby_platform
    zr_os_platform(Machine.bytes("aarch64"), 7)
  end
end
