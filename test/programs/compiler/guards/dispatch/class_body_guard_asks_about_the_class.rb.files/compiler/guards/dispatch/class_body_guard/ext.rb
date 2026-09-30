# Each reopen's body is ONE statement. The guard must ask `Plat`, the class
# that the body reopens, and not the outer module `Gm`.
module Gm
  require_relative "plat"

  class Plat
    unless respond_to?(:generic)
      WIDTH = 2
    end
  end

  class Plat
    if respond_to?(:generic)
      HEIGHT = 3
    end
  end

  class Plat
    unless const_defined?(:WIDTH)
      DEPTH = 4
    end
  end
end
