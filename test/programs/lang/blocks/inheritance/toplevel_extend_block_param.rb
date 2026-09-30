# A module method declaring &block, reached through a top-level extend, is
# called with the block argument.
module DSL
  def update(&proc)
    if proc
      proc.call
    else
      puts 'no block'
    end
  end

  def render(z: :foreground, &proc)
    puts "render #{z}"
    proc.call if proc
  end

  def plain(n)
    puts "plain #{n}"
  end
end

extend DSL

update { puts 'block ran' }
update
render(z: :background) { puts 'render block' }
render
plain 3
