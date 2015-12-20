`import Job from './job';`

Failure = Job.extend
  failed_at: DS.attr 'date'
  error_message: DS.attr 'string'

`export default Failure`
