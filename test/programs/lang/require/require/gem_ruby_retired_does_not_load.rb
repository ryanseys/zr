# A library ruby retired from its default and bundled gems, and that no
# gem installs here, does not load: the require raises LoadError, as in
# ruby. (webrick left the bundled gems too, but a host can install it.)
%w[net-telnet sdbm].each do |name|
  begin
    require name
    p [name, :loaded]
  rescue LoadError => e
    p [name, e.class, e.message, e.path]
  end
end
p defined?(SDBM)

