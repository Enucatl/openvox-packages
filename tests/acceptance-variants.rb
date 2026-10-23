require_relative 'acceptance/lifecycle-variants'

ubuntu = lifecycle_variants('ubuntu26.04')
raise 'Ubuntu lost CA import or setup coverage' unless ubuntu.map(&:last) == %w[RSA-lifecycle ML-DSA-44-lifecycle RSA-setup-lifecycle ML-DSA-44-setup-lifecycle]
raise 'Debian must test the full Vault ML-DSA agent lifecycle' unless lifecycle_variants('debian13') == [ubuntu.fetch(1)]
begin
  lifecycle_variants('ubuntu24.04')
  raise 'Accepted unsupported Ubuntu 24.04'
rescue RuntimeError => error
  raise unless error.message == 'Unsupported acceptance target: ubuntu24.04'
end
puts 'Acceptance lifecycle target coverage checks passed'
