ShowRoute = Ember.Route.extend
  model: (params) ->
    @store.find('queue', params.id)

`export default ShowRoute`