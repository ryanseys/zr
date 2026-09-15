# frozen_string_literal: true

# Where a table tool writes: the OS layer of the ruby running it, which
# is the OS whose numbers the tables hold. Each OS's ruby writes its own
# (a darwin ruby here, an Alpine ruby for linux, ruby.wasm under
# wasmtime for wasi), so no table is ever read off the wrong OS.
module Layer
  OS = RUBY_PLATFORM[/darwin|linux|wasi/] or abort("no OS layer for #{RUBY_PLATFORM}")
  ROOT = File.expand_path("..", __dir__)

  module_function

  # `rt/<part>/os/<os>/<name>`, as a path under the checkout.
  def path(part, name) = File.join(ROOT, "rt", part, "os", OS, name)

  # `text` written at `rt/<part>/os/<os>/<name>`, and a line saying so.
  def write(part, name, text)
    target = path(part, name)
    Dir.mkdir(File.dirname(target)) unless File.directory?(File.dirname(target))
    File.write(target, text)
    puts "#{target.delete_prefix("#{ROOT}/")}: #{text.lines.size} lines"
  end
end
