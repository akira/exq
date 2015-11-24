Failure = DS.Model.extend
  queue: DS.attr 'string'
  class: DS.attr 'string'
  args: DS.attr 'string'
  failed_at: DS.attr 'date'
  error_message: DS.attr 'string'

`export default Failure`
