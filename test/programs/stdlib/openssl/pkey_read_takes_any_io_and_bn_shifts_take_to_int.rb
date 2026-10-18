# ossl_obj2bio reads any IO (T_FILE), and BN's shifts take to_int.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

require "openssl"
key = OpenSSL::PKey::EC.generate("prime256v1")
t("pipe") { r, w = IO.pipe; w.write(key.to_pem); w.close; OpenSSL::PKey.read(r).to_pem == key.to_pem }
t("file") { require "tempfile"; Tempfile.create("pkey") { |f| f.write(key.to_pem); f.rewind; OpenSSL::PKey.read(f).class } }
o = Object.new
def o.to_int = 1
t("shift") { [(OpenSSL::BN.new(3) << o).to_i, (OpenSSL::BN.new(3) >> o).to_i, (OpenSSL::BN.new(3).lshift!(o)).to_i] }
