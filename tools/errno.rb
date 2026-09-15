# Writes rt/core/os/darwin/errno.rb: the errno and signal tables of the ruby the
# .ruby-version pins. Every Errno name is a row: one per class, with
# the errno it stands for, and the other names of a class as aliases
# (ruby gives the errnos this platform lacks one class, NOERROR).
# Signal.list is copied in ruby's own order.
errno = Errno.constants.group_by { |name| Errno.const_get(name) }.map do |klass, names|
  primary = klass.name.delete_prefix("Errno::").to_sym
  [primary, klass::Errno, (names - [primary]).sort]
end.sort_by { |name, code, _| [code, name] }

codes = errno.map { |name, code, _| "#{name}: #{code}" }
aliases = errno.flat_map { |name, _, others| others.map { |other| "#{other}: :#{name}" } }
signals = Signal.list.map { |name, number| "#{name.inspect} => #{number}" }

# The rows of a Hash literal, wrapped to the line width the core uses.
def rows(items, indent)
  lines = [+""]
  items.each do |item|
    lines << +"" if lines.last.size + item.size + 2 > 100 - indent
    lines.last << (lines.last.empty? ? item : " #{item}")
    lines.last << ","
  end
  lines.last.chomp!(",")
  lines.map { |line| (" " * indent) + line }.join("\n")
end

File.write(File.expand_path("../rt/core/os/darwin/errno.rb", __dir__), <<~RUBY)
  # Written by tools/errno.rb from ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}; do not edit.
  # Every Errno name and the errno it stands for, one row per class; a
  # name in ALIASES is another name for a class in CODES. Signal::LIST is
  # Signal.list in ruby's order.
  module Errno
    CODES = {
  #{rows(codes, 4)}
    }.freeze
    ALIASES = {
  #{rows(aliases, 4)}
    }.freeze
    private_constant :CODES, :ALIASES
  end

  module Signal
    LIST = {
  #{rows(signals, 4)}
    }.freeze
    private_constant :LIST
  end
RUBY
puts "rt/core/os/darwin/errno.rb: #{codes.size} classes, #{aliases.size} aliases, #{signals.size} signals"
