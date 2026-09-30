# Ruby isolates the Proc and rebinds its `self` to the RACTOR, so `@n` is
# an ivar of a shareable object -- `Ractor::IsolationError` in the ractor,
# surfacing as `Ractor::RemoteError` at `#value`.

Thread.report_on_exception = false
class Holder
  def initialize = @n = 7
  def go
    Ractor.new { @n }.value
  rescue Ractor::RemoteError => e
    puts "cause: #{e.cause.class}: #{e.cause.send(:message)}"
  end
end
Holder.new.go
