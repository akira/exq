Job = DS.Model.extend
  queue: DS.attr 'string'
  class: DS.attr 'string'
  args: DS.attr 'string'
  enqueued_at: DS.attr 'date'
  started_at: DS.attr 'date'
  
`export default Job`