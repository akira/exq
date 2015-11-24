IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.findAll('scheduled')

`export default IndexRoute`
