ShowRoute = Ember.Route.extend
  model: (params) ->
    @store.findRecord('queue', params.id).then (myModel) ->
      if myModel.get('partial')
        myModel.reload()


`export default ShowRoute`
