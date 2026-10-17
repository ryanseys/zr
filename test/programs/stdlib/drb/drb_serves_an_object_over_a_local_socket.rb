# dRuby serves an object on a local port, and a remote reference calls it.
require "drb/drb"
DRb.start_service("druby://127.0.0.1:0", [1, 2])
p DRbObject.new_with_uri(DRb.uri).size
DRb.stop_service
