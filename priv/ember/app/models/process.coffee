Process = DS.Model.extend
  pid:  DS.attr 'string'
  host: DS.attr 'string'
  job:  DS.belongsTo 'job'
  started_at: DS.attr 'date'

`export default Process`