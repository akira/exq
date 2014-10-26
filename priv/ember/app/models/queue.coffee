Queue = DS.Model.extend
  size: DS.attr 'number'
  jobs: DS.hasMany 'job'
  partial: true
`export default Queue`