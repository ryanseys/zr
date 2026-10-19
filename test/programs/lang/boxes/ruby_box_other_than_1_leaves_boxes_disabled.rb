# Only RUBY_BOX=1 enables boxes, as Init_enable_box reads it once at the
# start: a later write to ENV does not change it.
p Ruby::Box.enabled?
p defined?(Ruby::Box.main)
ENV["RUBY_BOX"] = "1"
p Ruby::Box.enabled?
begin
  Ruby::Box.new
rescue RuntimeError => e
  p e.message
end
