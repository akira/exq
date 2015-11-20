ApplicationRoute = Ember.Route.extend
  model: (params) ->
    @get('store').findRecord('stat', 'all')
  actions:
    reloadStats: ->
      @get('store').findRecord('stat', 'all').then((stats) ->
        stats.reload()
      )

`export default ApplicationRoute`
