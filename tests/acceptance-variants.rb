require_relative 'acceptance/lifecycle-variants'
require 'yaml'

ubuntu = lifecycle_variants('ubuntu26.04')
raise 'Ubuntu lost CA import or setup coverage' unless ubuntu.map(&:last) == %w[RSA-lifecycle ML-DSA-44-lifecycle RSA-setup-lifecycle ML-DSA-44-setup-lifecycle]
raise 'Debian must test the full Vault ML-DSA agent lifecycle' unless lifecycle_variants('debian13') == [ubuntu.fetch(1)]
groups = %w[rsa mldsa].map { |group| lifecycle_variants('ubuntu26.04', group) }
raise 'Parallel groups overlap or omit a lifecycle' unless groups.flatten(1).sort_by(&:last) == ubuntu.sort_by(&:last) && groups.flatten(1).uniq.size == ubuntu.size
raise 'RSA group includes another algorithm' unless groups.first.all? { |variant| variant.first == 'RSA' }
raise 'ML-DSA group includes another algorithm' unless groups.last.all? { |variant| variant.first == 'ML-DSA-44' }
raise 'Debian lost the full Vault lifecycle' unless lifecycle_variants('debian13', 'mldsa') == lifecycle_variants('debian13')
[['ubuntu26.04', 'invalid', 'Unsupported acceptance group: invalid'], ['debian13', 'rsa', 'No acceptance variants for debian13/rsa']].each do |target, group, message|
  begin
    lifecycle_variants(target, group)
    raise 'Accepted an invalid lifecycle group'
  rescue RuntimeError => error
    raise unless error.message == message
  end
end
begin
  lifecycle_variants('ubuntu24.04')
  raise 'Accepted unsupported Ubuntu 24.04'
rescue RuntimeError => error
  raise unless error.message == 'Unsupported acceptance target: ubuntu24.04'
end
puts 'Acceptance lifecycle target coverage checks passed'

workflow = YAML.load_file(File.expand_path('../.github/workflows/packages.yml', __dir__))
matrix = workflow.fetch('jobs').fetch('acceptance').fetch('strategy').fetch('matrix').fetch('include')
%w[ubuntu26.04 debian13].each do |target|
  selected = matrix.select { |entry| entry.fetch('target') == target }.flat_map { |entry| lifecycle_variants(target, entry.fetch('group')) }
  raise "Workflow duplicates or loses acceptance coverage for #{target}" unless selected.sort_by(&:last) == lifecycle_variants(target).sort_by(&:last)
end
puts 'Workflow lifecycle groups cover each supported variant exactly once'
