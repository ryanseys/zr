module Zr::Kern
  # RUBY_PLATFORM, as ruby built against musl gives it.
  #: () -> value
  def zr_os_ruby_platform
    zr_str_new(Machine.bytes("aarch64-linux-musl"), 18)
  end
end
