module.exports = {
  printWidth: 100,
  tabWidth: 2,
  singleQuote: true,
  trailingComma: 'none',
  semi: true,
  parser: 'babel',
  overrides: [
    {
      files: ['*.js', '*.jsx'],
      options: {
        parser: 'babel'
      }
    },
    {
      files: ['*.ts', '*.tsx'],
      options: {
        parser: 'typescript'
      }
    },
    {
      files: ['*.json', '*.jsonc', '.*rc'],
      options: { parser: 'json' }
    },
    {
      files: ['*.css', '*.scss', '.*less'],
      options: { parser: 'css' }
    }
  ]
};module.exports = {
  printWidth: 100,
  tabWidth: 2,
  singleQuote: true,
  trailingComma: 'none',
  semi: true,
  parser: 'babel',
  overrides: [
    {
      files: ['*.js', '*.jsx'],
      options: {
        parser: 'babel'
      }
    },
    {
      files: ['*.ts', '*.tsx'],
      options: {
        parser: 'typescript'
      }
    },
    {
      files: ['*.json', '*.jsonc', '.*rc'],
      options: { parser: 'json' }
    },
    {
      files: ['*.css', '*.scss', '.*less'],
      options: { parser: 'css' }
    }
  ]
};
