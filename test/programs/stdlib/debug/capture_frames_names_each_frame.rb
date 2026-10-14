# The debug gem's C half gives each frame from the caller outward, as a
# FrameInfo of the gem's Ruby half, and the depth of the stack.
require "debug/frame_info"
require "debug/debug.so"

class Probe
  def outer = inner { |frames| frames }
  def inner = yield(DEBUGGER__.capture_frames("/nowhere/"))
end

frames = Probe.new.outer
frames.first(4).each do |frame|
  p [frame.location.label, frame.location.lineno, frame.self.class]
end
p DEBUGGER__.frame_depth.positive?, DEBUGGER__::SO_VERSION
