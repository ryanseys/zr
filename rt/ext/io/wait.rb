# frozen_string_literal: true

# Waiting on one descriptor, over poll(2). Named events answer the
# stream itself; a plain events mask answers the events that came ready.

class IO
  POLL_IN = 0x0001
  POLL_PRI = 0x0002
  POLL_OUT = 0x0004
  private_constant :POLL_IN, :POLL_PRI, :POLL_OUT

  EVENT_NAMES = { read: POLL_IN, readable: POLL_IN, r: POLL_IN,
                  write: POLL_OUT, writable: POLL_OUT, w: POLL_OUT,
                  priority: POLL_PRI, rw: POLL_IN | POLL_OUT }.freeze
  private_constant :EVENT_NAMES

  def wait(*args)
    if args.size == 2 && args.all? { |arg| arg.is_a?(Numeric) }
      ready = poll_once(args[0].to_int, args[1])
      return ready.zero? ? nil : ready
    end
    events = 0
    timeout = nil
    args.each do |arg|
      case arg
      when Symbol then events |= EVENT_NAMES.fetch(arg) { raise ArgumentError, "unsupported mode: #{arg}" }
      when Numeric, nil then timeout = arg
      else raise TypeError, "no implicit conversion of #{arg.class} into Integer"
      end
    end
    poll_once(events.zero? ? POLL_IN : events, timeout).zero? ? nil : self
  end

  def wait_readable(timeout = nil) = poll_once(POLL_IN, timeout).zero? ? nil : self

  def wait_writable(timeout = nil) = poll_once(POLL_OUT, timeout).zero? ? nil : self

  def wait_priority(timeout = nil) = poll_once(POLL_PRI, timeout).zero? ? nil : self

  private

  # The events that came ready, or zero when the time ran out.
  def poll_once(events, timeout)
    ready = Primitive.zr_io_wait(fileno, events, timeout.nil? ? -1 : (timeout * 1000).round)
    raise SystemCallError.new("@ io_wait - #{label}", -ready) if ready.negative?

    ready & events
  end
end
