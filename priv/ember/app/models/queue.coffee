Queue = DS.Model.extend
  size: DS.attr 'number'
  jobs: DS.hasMany 'job'
`export default Queue`