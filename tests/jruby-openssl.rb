require 'openssl'

%w[ML-DSA-44 ML-DSA-65 ML-DSA-87].each do |algorithm|
  key = OpenSSL::PKey.generate_key(algorithm)
  public_key = OpenSSL::PKey.read(key.public_to_pem)
  signature = key.sign(nil, 'coordinated release')
  raise "#{algorithm} signature failed" unless public_key.verify(nil, signature, 'coordinated release')
  raise "#{algorithm} accepted altered data" if public_key.verify(nil, signature, 'altered')
end
puts "jruby-openssl #{Gem.loaded_specs.fetch('jruby-openssl').version}: ML-DSA signing and verification passed"
