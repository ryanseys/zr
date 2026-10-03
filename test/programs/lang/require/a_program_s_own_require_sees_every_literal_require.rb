$LOAD_PATH.unshift File.expand_path("traced_requires/lib")
module Kernel
  alias_method :untraced_require, :require
  def require(feature)
    puts "require #{feature}"
    untraced_require(feature)
  end
end
p require("tr_alpha")
p require("tr_alpha")
p TR_ALPHA + TR_BETA
