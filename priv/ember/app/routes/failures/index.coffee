IndexRoute = Ember.Route.extend
  model: (params) ->
    @store.find('failure')

`export default IndexRoute`