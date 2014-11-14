ApplicationRoute = Ember.Route.extend
  model: (params) ->
    @get('store').find('stat', 'all')  
  actions:
    reloadStats: ->
      @get('store').find('stat', 'all').then((stats) ->
        stats.reload()
      )

`export default ApplicationRoute`


