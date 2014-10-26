IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.find('process')

`export default IndexRoute`