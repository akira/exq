ShowRoute = Ember.Route.extend
  model: (params) ->
    @store.find('queue', params.id).then (myModel) ->
      if myModel.get('partial')
        myModel.reload()


`export default ShowRoute`