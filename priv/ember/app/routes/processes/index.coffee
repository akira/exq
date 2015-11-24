IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.findAll('process')

`export default IndexRoute`
