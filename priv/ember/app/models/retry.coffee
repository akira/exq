Retry = DS.Model.extend
  queue: DS.attr 'string'
  class: DS.attr 'string'
  args: DS.attr 'string'
  failed_at: DS.attr 'date'
  error_message: DS.attr 'string'
  retry: DS.attr 'boolean'
  retry_count: DS.attr 'number'

`export default Retry`
