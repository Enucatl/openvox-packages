def lifecycle_variants(target, group = 'all')
  raise "Unsupported acceptance group: #{group}" unless %w[all rsa mldsa].include?(group)
  imported_mldsa = ['ML-DSA-44', 'mldsa44', 'vault-state', 'ML-DSA-44-lifecycle']
  variants = case target
  when 'ubuntu26.04'
    [
      ['RSA', 'rsa', 'RSA', 'RSA-lifecycle'],
      imported_mldsa,
      ['RSA', 'rsa', nil, 'RSA-setup-lifecycle'],
      ['ML-DSA-44', 'mldsa44', nil, 'ML-DSA-44-setup-lifecycle']
    ]
  when 'debian13'
    [imported_mldsa]
  else
    raise "Unsupported acceptance target: #{target}"
  end
  variants = variants.select { |algorithm, *| algorithm == (group == 'rsa' ? 'RSA' : 'ML-DSA-44') } unless group == 'all'
  raise "No acceptance variants for #{target}/#{group}" if variants.empty?
  variants
end
