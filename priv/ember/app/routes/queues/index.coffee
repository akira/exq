IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.findAll('queue')

`export default IndexRoute`
