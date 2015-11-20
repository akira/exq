`import ActiveModelAdapter from 'active-model-adapter'`

ApplicationAdapter = ActiveModelAdapter.extend
  namespace: "#{window.exqNamespace}api"

`export default ApplicationAdapter`
