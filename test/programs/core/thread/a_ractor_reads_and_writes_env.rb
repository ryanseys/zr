# ENV is shareable, as CRuby marks it, so a ractor other than the main
# one reads and writes it (test_env.rb's test_bracket_in_ractor).
p Ractor.shareable?(ENV), ENV.frozen?
r = Ractor.new port = Ractor::Port.new do |port|
  port << ENV['zr_test']
  ENV['zr_test'] = 'foo'
  port << ENV['zr_test']
  e = nil
  begin
    ENV[1] = 'x'
  rescue Exception => ex
    e = ex
  end
  port.send e.class
  port << ENV['zr_test'].frozen?
end
p 4.times.map { port.receive }
r.join
p ENV['zr_test'], ENV['zr_test'].frozen?
