$LOAD_PATH.unshift(ENV.fetch("NO_SUCH_VARIABLE", File.expand_path("computed_path/alt")))
require "base64"
p defined?(Base64::ALT)
