module Kernel
  alias_method :zr_orig_frozen, :frozen?
  private :zr_orig_frozen
end
