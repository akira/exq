IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.findAll('retry')

`export default IndexRoute`
