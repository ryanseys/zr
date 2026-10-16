# IO::Buffer#read, #write, #pread and #pwrite ask the fiber scheduler
# whether it takes the call. That question (respond_to?) can run Ruby
# that changes the view, so the view is checked again before the system
# call, as rb_io_buffer_read does: a view the probe emptied raises.
require "tempfile"
Warning[:experimental] = false

class Probing
  attr_accessor :probe_method, :probe_buffer, :change

  def respond_to?(name, include_private = false)
    if name == @probe_method && @probe_buffer
      buffer = @probe_buffer
      @probe_buffer = nil
      @change.call(buffer)
      return false
    end
    super
  end

  def block(*) = nil
  def unblock(*) = nil
  def kernel_sleep(*) = nil
  def io_wait(*) = nil
  def fiber_interrupt(*) = nil
  def close = nil
  def fiber(&block) = Fiber.new(blocking: false, &block).tap(&:resume)
end

[[:resize, ->(view) { view.resize(0) }], [:advance, ->(view) { view.advance(view.size) }]].each do |kind, change|
  %i[read write pread pwrite].each do |method|
    buffer = IO::Buffer.new(8)
    buffer.set_string("AAAABBBB")
    view = buffer.slice(0, 4)
    Tempfile.create("io-buffer-probe") do |file|
      file.binmode
      file.write("cccccccc")
      file.rewind
      got = Thread.new do
        scheduler = Probing.new
        Fiber.set_scheduler(scheduler)
        answer = nil
        Fiber.schedule do
          scheduler.probe_method = :"io_#{method}"
          scheduler.probe_buffer = view
          scheduler.change = change
          args = [file]
          args << 0 if %i[pread pwrite].include?(method)
          answer = begin
            view.public_send(method, *args)
          rescue => e
            [e.class, e.message]
          end
        end
        answer
      end.value
      file.rewind
      p [kind, method, got, view.empty?, buffer.locked?, buffer.get_string, file.read]
    end
    buffer.free
  end
end
