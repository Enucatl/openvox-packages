def lifecycle_variants(target)
  imported_mldsa = ['ML-DSA-44', 'mldsa44', 'vault-state', 'ML-DSA-44-lifecycle']
  case target
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
end
