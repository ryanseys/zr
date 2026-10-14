# An extension's C defines its module with rb_define_module, which
# raises TypeError when the constant already holds something else.
[%w[Coverage coverage], %w[NKF nkf], %w[PTY pty], %w[Fcntl fcntl]].each do |name, feature|
  Object.const_set(name, 1)
  begin
    require feature
    puts "#{feature}: loaded"
  rescue TypeError => e
    puts "#{feature}: #{e.class}: #{e.message}"
  ensure
    Object.send(:remove_const, name)
  end
end
