IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.findAll('failure')

`export default IndexRoute`
