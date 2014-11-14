IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.find('queue')

`export default IndexRoute`