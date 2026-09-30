# `autoload :Const, "#{__dir__}/sibling"` -- how puma, rack and sidekiq name a
# sibling file. zr splices the target at compile time, so the interpolation
# has to fold then; only a plain literal and `File.expand_path` did.

autoload :Sprocket, "#{__dir__}/autoload_interp/sprocket"
autoload :Widget, "#{__dir__}/autoload_interp/sprocket"

p Sprocket.size
p Widget::NAME
p Sprocket.is_a?(Class)
